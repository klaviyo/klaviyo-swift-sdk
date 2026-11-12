#!/bin/bash
# bump-version.sh - Update SDK version across all files in the repository
#
# Usage:
#   ./bump-version.sh [version]
#
# If version is not provided, the script will prompt for it.

set -e

# In-place sed that works with both BSD (macOS) and GNU (Linux) sed.
sed_inplace() {
  local file="${@: -1}"
  sed -i.bak "$@" && rm -f "$file.bak"
}

# File paths
VERSION_SWIFT="Sources/KlaviyoCore/Utils/Version.swift"

# Extract current version from Version.swift
currentVersion=$(grep '__klaviyoSwiftVersion' "$VERSION_SWIFT" | sed 's/.*"\(.*\)"/\1/')

if [[ -z "$currentVersion" ]]; then
  echo "Error: Could not extract current version from $VERSION_SWIFT"
  exit 1
fi

# Get new version from argument or prompt
if [[ -z "$1" ]]; then
  echo "Current version: $currentVersion"
  read -rp "Enter new version: " newVersion
else
  newVersion="$1"
fi

# Validate input
if [[ -z "$newVersion" ]]; then
  echo "Error: Version cannot be empty"
  exit 1
fi

if [[ "$newVersion" == "$currentVersion" ]]; then
  echo "Version is already $currentVersion - nothing to do"
  exit 0
fi

echo "Bumping version: $currentVersion -> $newVersion"
echo ""

# 1. Update Version.swift
echo "Updating $VERSION_SWIFT..."
sed_inplace "s/__klaviyoSwiftVersion = \"$currentVersion\"/__klaviyoSwiftVersion = \"$newVersion\"/" "$VERSION_SWIFT"

# 2. Update podspecs
echo "Updating podspecs..."

for podspec in *.podspec; do
  sed_inplace "s/s.version          = \"$currentVersion\"/s.version          = \"$newVersion\"/" "$podspec"
  # matches any s.dependency 'Klaviyo<Module>', '~> <version>' pin
  sed_inplace "s/'Klaviyo\([A-Za-z]*\)', '~> $currentVersion'/'Klaviyo\1', '~> $newVersion'/g" "$podspec"
done

# 3. Update test files/snapshots with hardcoded versions
echo "Updating test files..."

# NetworkSessionTests.swift
sed_inplace "s/klaviyo-swift\/$currentVersion/klaviyo-swift\/$newVersion/g" "Tests/KlaviyoCoreTests/NetworkSessionTests.swift"

echo "Updating test snapshots..."

escapedCurrent="${currentVersion//./\\.}"

while IFS= read -r snapshot; do
  sed_inplace -E "s/(^|[^0-9.])$escapedCurrent($|[^0-9.])/\1$newVersion\2/g" "$snapshot"
done < <(find Tests -type d -name __Snapshots__ -exec grep -rlF "$currentVersion" {} + 2>/dev/null)

# 4. Update example app Podfile
EXAMPLE_PODFILE="Examples/KlaviyoSwiftExamples/CocoapodsExample/Podfile"
if [[ -f "$EXAMPLE_PODFILE" ]]; then
  echo "Updating $EXAMPLE_PODFILE..."
  # Update version-pinned pod references
  sed_inplace "s/'KlaviyoSwift', '$currentVersion'/'KlaviyoSwift', '$newVersion'/g" "$EXAMPLE_PODFILE"
  sed_inplace "s/'KlaviyoForms', '$currentVersion'/'KlaviyoForms', '$newVersion'/g" "$EXAMPLE_PODFILE"
  sed_inplace "s/'KlaviyoSwiftExtension', '$currentVersion'/'KlaviyoSwiftExtension', '$newVersion'/g" "$EXAMPLE_PODFILE"
  sed_inplace "s/'KlaviyoLocation', '$currentVersion'/'KlaviyoLocation', '$newVersion'/g" "$EXAMPLE_PODFILE"
fi

# 5. Update example app project marketing versions
echo "Updating example app project versions..."

COCOAPODS_PROJECT="Examples/KlaviyoSwiftExamples/CocoapodsExample/CocoapodsExample.xcodeproj/project.pbxproj"
if [[ -f "$COCOAPODS_PROJECT" ]]; then
  sed_inplace "s/MARKETING_VERSION = $currentVersion;/MARKETING_VERSION = $newVersion;/g" "$COCOAPODS_PROJECT"
fi

SPM_PROJECT="Examples/KlaviyoSwiftExamples/SPMExample/SPMExample.xcodeproj/project.pbxproj"
if [[ -f "$SPM_PROJECT" ]]; then
  sed_inplace "s/MARKETING_VERSION = $currentVersion;/MARKETING_VERSION = $newVersion;/g" "$SPM_PROJECT"
fi

echo ""
echo "✅ Version bumped from $currentVersion to $newVersion"
