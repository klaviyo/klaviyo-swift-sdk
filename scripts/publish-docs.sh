#!/usr/bin/env bash
#
# Stages one SDK version's DocC site into a GitHub Pages `docs/` tree. The docs-publish workflow
# runs this against the `documentation` branch; `make docs-publish-dry-run` runs it locally so the
# exact tree the workflow would commit can be inspected.
#
# Usage:
#   scripts/publish-docs.sh --version <X.Y.Z> --docs-dir <dir> [--source <dir>] [--site-url <url>]
#
#   --version   Release version. Its major.minor names the folder, so a patch release overwrites its
#               minor's folder. Prereleases are rejected.
#   --docs-dir  The `docs/` folder Pages serves (created if missing). Other versions in it are kept.
#   --source    SDK checkout to document. Default: this repo. If it has no scripts/build-docs.sh
#               (tags before DocC landed), this repo's copy is used.
#   --site-url  Public URL of the Pages site. Default: https://klaviyo.github.io/klaviyo-swift-sdk
#
# Resulting tree:
#   docs/<major.minor>/  built with base path <site path>/<major.minor>. Every page gets
#                        `noindex` and a canonical link to the same page under latest/.
#   docs/latest/         rebuilt with base path <site path>/latest, only when <major.minor> is the
#                        highest version in docs/. Every page gets a self-referencing canonical link.
#   docs/index.html      redirects to latest/.
#   docs/.nojekyll       stops Pages running Jekyll over the output.

set -euo pipefail

TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
DOCS_DIR=""
SOURCE="$TOOLS_ROOT"
SITE_URL="https://klaviyo.github.io/klaviyo-swift-sdk"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --docs-dir) DOCS_DIR="${2:?--docs-dir needs a value}"; shift 2 ;;
        --source) SOURCE="${2:?--source needs a value}"; shift 2 ;;
        --site-url) SITE_URL="${2:?--site-url needs a value}"; shift 2 ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 64 ;;
    esac
done

[[ -n "$VERSION" && -n "$DOCS_DIR" ]] || { echo "error: --version and --docs-dir are required" >&2; exit 64; }
VERSION="${VERSION#v}"
if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
    echo "error: version must be X.Y.Z (prereleases aren't published), got '$VERSION'" >&2
    exit 64
fi
MINOR="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"

SITE_URL="${SITE_URL%/}"
# Path the site is served under, e.g. "klaviyo-swift-sdk" for https://klaviyo.github.io/klaviyo-swift-sdk.
SITE_PATH="$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.urlparse(sys.argv[1]).path.strip("/"))' "$SITE_URL")"
prefixed() { echo "${SITE_PATH:+$SITE_PATH/}$1"; }

SOURCE="$(cd "$SOURCE" && pwd)"
mkdir -p "$DOCS_DIR"
DOCS_DIR="$(cd "$DOCS_DIR" && pwd)"

BUILD_SCRIPT="$SOURCE/scripts/build-docs.sh"
if [[ ! -x "$BUILD_SCRIPT" ]]; then
    echo "==> $SOURCE has no scripts/build-docs.sh; using $TOOLS_ROOT/scripts/build-docs.sh"
    mkdir -p "$SOURCE/scripts"
    cp "$TOOLS_ROOT/scripts/build-docs.sh" "$BUILD_SCRIPT"
fi

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/publish-docs.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

# Adds SEO tags to every HTML page in a built site. DocC writes the same SPA shell to every page,
# so each page's canonical URL is derived from its path in the site.
#   tag_pages <site dir> <canonical folder> <noindex 0|1>
tag_pages() {
    python3 -I - "$1" "$SITE_URL/$2" "$3" <<'PY'
import pathlib, re, sys, urllib.parse
site, canonical_root, noindex = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "1"
existing_canonical = re.compile(r'<link rel="canonical"[^>]*>\s*')
count = 0
for page in site.rglob("*.html"):
    rel = page.relative_to(site).as_posix()
    rel = rel[: -len("index.html")] if rel.endswith("index.html") else rel
    rel = urllib.parse.quote(rel, safe="/:()")
    tags = f'<link rel="canonical" href="{canonical_root}/{rel}">'
    if noindex:
        tags += '<meta name="robots" content="noindex">'
    html = existing_canonical.sub("", page.read_text())
    html, n = re.subn(r"<head>", "<head>" + tags, html, count=1)
    if n != 1:
        sys.exit(f"error: no <head> in {page}")
    page.write_text(html)
    count += 1
print(f"    tagged {count} pages (canonical: {canonical_root}/, noindex: {noindex})")
PY
}

# Builds the site for <folder> and swaps it into docs/<folder>.
#   publish_folder <folder> <canonical folder> <noindex 0|1>
publish_folder() {
    local folder="$1" out="$STAGING/$1"
    echo "==> Building $VERSION for /$(prefixed "$folder")/"
    "$BUILD_SCRIPT" --hosting-base-path "$(prefixed "$folder")" --output "$out"
    tag_pages "$out" "$2" "$3"
    rm -rf "${DOCS_DIR:?}/$folder"
    mv "$out" "$DOCS_DIR/$folder"
}

publish_folder "$MINOR" latest 1

# Only the highest published minor feeds latest/, so a patch to an older minor leaves it alone.
highest="$(find "$DOCS_DIR" -mindepth 1 -maxdepth 1 -type d -print | sed 's|.*/||' \
    | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
if [[ "$highest" == "$MINOR" ]]; then
    publish_folder latest latest 0
    UPDATED_LATEST=true
else
    echo "==> $MINOR is older than $highest; leaving latest/ as-is"
    UPDATED_LATEST=false
fi

cat > "$DOCS_DIR/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Klaviyo Swift SDK</title>
  <meta http-equiv="refresh" content="0; url=/$(prefixed latest)/">
  <link rel="canonical" href="$SITE_URL/latest/">
</head>
<body><a href="/$(prefixed latest)/">Klaviyo Swift SDK documentation</a></body>
</html>
HTML
touch "$DOCS_DIR/.nojekyll"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "minor=$MINOR"
        echo "updated_latest=$UPDATED_LATEST"
    } >> "$GITHUB_OUTPUT"
fi
echo "==> Done: $DOCS_DIR/$MINOR$([[ "$UPDATED_LATEST" == true ]] && echo " and $DOCS_DIR/latest")"
