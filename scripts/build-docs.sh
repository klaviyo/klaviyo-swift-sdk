#!/usr/bin/env bash
#
# Builds the combined DocC static site for the public SDK products.
#
# Usage:
#   scripts/build-docs.sh [--hosting-base-path <path>] [--output <dir>] [--strict]
#
#   --hosting-base-path  Base path the site is served from, e.g. "klaviyo-swift-sdk/5.6".
#                        Leading/trailing slashes are optional. Default: "" (served from "/").
#   --output             Output directory for the static site. Default: build/docs/site
#   --strict             Exit non-zero if DocC reports any warnings for the documented products.
#
# How it works:
#   1. `xcodebuild docbuild` builds one .doccarchive per module for the iOS Simulator.
#      (`swift-docc-plugin` can't be used: the package depends on UIKit, so SwiftPM can't
#      build it for the host, and SwiftPM's iOS cross-compile rejects our iOS 13 floor.)
#   2. `docc merge` combines the archives of the library products declared in Package.swift.
#      KlaviyoCore and AnyCodable are built as dependencies but are not merged, so KlaviyoCore's
#      own declarations get no pages. Public extensions that a product declares on KlaviyoCore
#      types (e.g. `registerForInAppForms` on `KlaviyoSDKModule`) still appear under that
#      product's "Extended Modules" section, because they are the product's API.
#   3. `docc process-archive transform-for-static-hosting` applies the hosting base path.
#
# The site is built into a staging directory and only replaces --output once every step succeeds.

set -euo pipefail

SCHEME="klaviyo-swift-sdk-Package"
LANDING_PAGE_NAME="Klaviyo Swift SDK"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
BASE_PATH=""
OUTPUT="$REPO_ROOT/build/docs/site"
STRICT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hosting-base-path) BASE_PATH="${2?--hosting-base-path needs a value}"; shift 2 ;;
        --output) OUTPUT="${2:?--output needs a value}"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 64 ;;
    esac
done

# Normalize to no leading/trailing slash; DocC expects "a/b", and an empty value means "/".
BASE_PATH="${BASE_PATH#/}"
BASE_PATH="${BASE_PATH%/}"

# Refuse output paths that would make the final `rm -rf` dangerous: "/", $HOME, the repo itself,
# or any directory that contains the repo.
OUTPUT="$(python3 -I -c 'import os, sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$OUTPUT")"
if [[ "$OUTPUT" == "/" || "$OUTPUT" == "$HOME" || "$REPO_ROOT/" == "$OUTPUT/"* ]]; then
    echo "error: refusing to use '$OUTPUT' as the output directory" >&2
    exit 64
fi

# The library products declared in Package.swift are the modules we document.
PRODUCTS=()
while IFS= read -r product; do PRODUCTS+=("$product"); done < <(
    swift package dump-package | python3 -I -c \
        'import json, sys; [print(p["name"]) for p in json.load(sys.stdin)["products"] if "library" in p["type"]]'
)
[[ ${#PRODUCTS[@]} -gt 0 ]] || { echo "error: no library products found in Package.swift" >&2; exit 1; }

WORK_DIR="$REPO_ROOT/build/docs"
DERIVED_DATA="$WORK_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Debug-iphonesimulator"
INTERMEDIATES_DIR="$DERIVED_DATA/Build/Intermediates.noindex/klaviyo-swift-sdk.build/Debug-iphonesimulator"
MERGED_ARCHIVE="$WORK_DIR/KlaviyoSwiftSDK.doccarchive"
STAGING="$WORK_DIR/site.staging"
LOG_FILE="$WORK_DIR/docbuild.log"

mkdir -p "$WORK_DIR"
# Incremental docbuilds don't re-run DocC for modules whose only changes are doc comments on
# extensions of another module's types, which leaves stale pages and stale diagnostics. Drop the
# build products every run; the SourcePackages checkout cache next to them is kept.
rm -rf "$DERIVED_DATA/Build" "$MERGED_ARCHIVE" "$STAGING"

echo "==> Building documentation archives (log: $LOG_FILE)"
if ! xcodebuild docbuild \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    > "$LOG_FILE" 2>&1; then
    tail -40 "$LOG_FILE" >&2
    echo "error: xcodebuild docbuild failed; see $LOG_FILE" >&2
    exit 1
fi

echo "==> Checking DocC diagnostics"
warning_count=0
for product in "${PRODUCTS[@]}"; do
    diagnostics="$INTERMEDIATES_DIR/$product-t.build/$product-diagnostics.json"
    if [[ ! -f "$diagnostics" ]]; then
        echo "error: no DocC diagnostics file for $product" >&2
        exit 1
    fi
    count="$(python3 -I - "$diagnostics" "$product" "$REPO_ROOT/" <<'PY'
import json, os, sys
path, product, root = sys.argv[1], sys.argv[2], sys.argv[3]
diagnostics = json.load(open(path))["diagnostics"]
annotate = os.environ.get("GITHUB_ACTIONS") == "true"
for d in diagnostics:
    source = d.get("source", "").removeprefix("file://").removeprefix(root)
    line = d.get("range", {}).get("start", {}).get("line", "?")
    print(f"  {d['severity']}: {product}: {source}:{line}: {d['summary']}", file=sys.stderr)
    if annotate:
        # Workflow command, so GitHub shows the diagnostic on the PR diff.
        level = "error" if d["severity"] == "error" else "warning"
        print(f"::{level} file={source},line={line},title=DocC ({product})::{d['summary']}", file=sys.stderr)
print(len(diagnostics))
PY
)"
    warning_count=$((warning_count + count))
done
echo "    $warning_count DocC diagnostic(s) across ${#PRODUCTS[@]} products"

if [[ "$STRICT" == "1" && "$warning_count" -gt 0 ]]; then
    echo "error: --strict set and DocC reported $warning_count diagnostic(s)" >&2
    exit 1
fi

echo "==> Merging ${PRODUCTS[*]}"
archives=()
for product in "${PRODUCTS[@]}"; do
    archives+=("$PRODUCTS_DIR/$product.doccarchive")
done
xcrun docc merge "${archives[@]}" \
    --synthesized-landing-page-name "$LANDING_PAGE_NAME" \
    --synthesized-landing-page-kind "SDK" \
    --output-path "$MERGED_ARCHIVE"

echo "==> Transforming for static hosting (base path: /${BASE_PATH})"
xcrun docc process-archive transform-for-static-hosting "$MERGED_ARCHIVE" \
    --output-path "$STAGING" \
    ${BASE_PATH:+--hosting-base-path "$BASE_PATH"}

# The archive's root index.html is an unconfigured template; send visitors to the landing page.
cat > "$STAGING/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>$LANDING_PAGE_NAME</title>
  <meta http-equiv="refresh" content="0; url=documentation/">
  <link rel="canonical" href="documentation/">
</head>
<body><a href="documentation/">$LANDING_PAGE_NAME documentation</a></body>
</html>
HTML

rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
mv "$STAGING" "$OUTPUT"

echo "==> Done: $OUTPUT"
echo "    Preview: make docs-serve${BASE_PATH:+ DOCS_BASE_PATH=$BASE_PATH}"
