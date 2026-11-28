#!/usr/bin/env bash
# Checks that Version.swift and every *.podspec match the expected version.
# Usage: scripts/check-version.sh <version>
# Exits 1 on mismatch. When GITHUB_ENV is set, exports VERSION_NAME, SWIFT_VERSION,
# PODSPEC_VERSIONS and ERROR_MESSAGE on failure for later Slack steps.
set -uo pipefail

VERSION_NAME="${1:?usage: check-version.sh <version>}"

SWIFT_VERSION=$(grep -o '__klaviyoSwiftVersion = "[^"]*"' Sources/KlaviyoCore/Utils/Version.swift | sed 's/.*"\([^"]*\)".*/\1/')
echo "Version.swift version: $SWIFT_VERSION"

PODSPEC_VERSIONS=""
PODSPEC_ERRORS=""
for podspec in *.podspec; do
  if [ -f "$podspec" ]; then
    PODSPEC_VERSION=$(grep -o 's\.version.*=.*"[^"]*"' "$podspec" | sed 's/.*"\([^"]*\)".*/\1/')
    echo "Podspec $podspec version: $PODSPEC_VERSION"
    if [ "$VERSION_NAME" != "$PODSPEC_VERSION" ]; then
      PODSPEC_ERRORS="$PODSPEC_ERRORS\n❌ $podspec version mismatch: expected $VERSION_NAME, found $PODSPEC_VERSION"
    else
      echo "✅ $podspec version matches: $PODSPEC_VERSION"
    fi
    PODSPEC_VERSIONS="$PODSPEC_VERSIONS $podspec:$PODSPEC_VERSION"
  fi
done

if [ "$VERSION_NAME" = "$SWIFT_VERSION" ] && [ -z "$PODSPEC_ERRORS" ]; then
  echo "✅ All version matches confirmed: $VERSION_NAME"
  exit 0
fi

ERROR_MESSAGE="❌ Version mismatch detected!"
if [ "$VERSION_NAME" != "$SWIFT_VERSION" ]; then
  ERROR_MESSAGE="$ERROR_MESSAGE\n❌ Version.swift mismatch: expected $VERSION_NAME, found $SWIFT_VERSION"
fi
if [ -n "$PODSPEC_ERRORS" ]; then
  ERROR_MESSAGE="$ERROR_MESSAGE$PODSPEC_ERRORS"
fi
ERROR_MESSAGE="$ERROR_MESSAGE\n\nPlease update version numbers in Sources/KlaviyoCore/Utils/Version.swift and all *.podspec files (or correct the branch/tag name)."
echo -e "$ERROR_MESSAGE"
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "VERSION_NAME=$VERSION_NAME"
    echo "SWIFT_VERSION=$SWIFT_VERSION"
    echo "PODSPEC_VERSIONS=$PODSPEC_VERSIONS"
    echo "ERROR_MESSAGE=$ERROR_MESSAGE"
  } >> "$GITHUB_ENV"
fi
exit 1
