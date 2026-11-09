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
# Environment overrides: DOCS_HOSTING_BASE_PATH, DOCS_OUTPUT, DOCC_STRICT=1.
#
# How it works:
#   1. `xcodebuild docbuild` builds one .doccarchive per module for the iOS Simulator.
#      (`swift-docc-plugin` can't be used: the package depends on UIKit, so SwiftPM can't
#      build it for the host, and SwiftPM's iOS cross-compile rejects our iOS 13 floor.)
#   2. `docc merge` combines only the archives in PRODUCTS into one archive. KlaviyoCore and
#      AnyCodable are built as dependencies but are left out of the merge, so their internal
#      `public` plumbing never reaches the site.
#   3. `docc process-archive transform-for-static-hosting` applies the hosting base path.

set -euo pipefail

# Public products to document. Keep in sync with the `products` in Package.swift.
PRODUCTS=(KlaviyoSwift KlaviyoForms KlaviyoLocation KlaviyoSwiftExtension)
SCHEME="klaviyo-swift-sdk-Package"
LANDING_PAGE_NAME="Klaviyo Swift SDK"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PATH="${DOCS_HOSTING_BASE_PATH:-}"
OUTPUT="${DOCS_OUTPUT:-$REPO_ROOT/build/docs/site}"
STRICT="${DOCC_STRICT:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hosting-base-path) BASE_PATH="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 64 ;;
    esac
done

# Normalize to no leading/trailing slash; DocC expects "a/b", and an empty value means "/".
BASE_PATH="${BASE_PATH#/}"
BASE_PATH="${BASE_PATH%/}"

WORK_DIR="$REPO_ROOT/build/docs"
DERIVED_DATA="$WORK_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Debug-iphonesimulator"
MERGED_ARCHIVE="$WORK_DIR/KlaviyoSwiftSDK.doccarchive"
LOG_FILE="$WORK_DIR/docbuild.log"

mkdir -p "$WORK_DIR"
rm -rf "$MERGED_ARCHIVE" "$OUTPUT"

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
    diagnostics="$(find "$DERIVED_DATA/Build/Intermediates.noindex" \
        -name "$product-diagnostics.json" -print -quit)"
    if [[ -z "$diagnostics" ]]; then
        echo "error: no DocC diagnostics file for $product" >&2
        exit 1
    fi
    count="$(python3 -I - "$diagnostics" "$product" "$REPO_ROOT/" <<'PY'
import json, sys
path, product, root = sys.argv[1], sys.argv[2], sys.argv[3]
diagnostics = json.load(open(path))["diagnostics"]
for d in diagnostics:
    source = d.get("source", "").removeprefix("file://").removeprefix(root)
    line = d.get("range", {}).get("start", {}).get("line", "?")
    print(f"  {d['severity']}: {product}: {source}:{line}: {d['summary']}", file=sys.stderr)
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
    --output-path "$OUTPUT" \
    ${BASE_PATH:+--hosting-base-path "$BASE_PATH"}

# The archive's root index.html is an unconfigured template; send visitors to the landing page.
cat > "$OUTPUT/index.html" <<HTML
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

echo "==> Done: $OUTPUT"
echo "    Preview: make docs-serve${BASE_PATH:+ DOCS_BASE_PATH=$BASE_PATH}"
