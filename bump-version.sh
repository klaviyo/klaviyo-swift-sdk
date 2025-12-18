#!/bin/bash
# bump-version.sh - Update SDK version across all files in the repository
#
# Usage:
#   ./bump-version.sh [version]
#
# If version is not provided, the script will prompt for it.

set -e

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
sed -i '' "s/__klaviyoSwiftVersion = \"$currentVersion\"/__klaviyoSwiftVersion = \"$newVersion\"/" "$VERSION_SWIFT"

# 2. Update podspecs
echo "Updating podspecs..."

# KlaviyoCore.podspec - version only
sed -i '' "s/s.version          = \"$currentVersion\"/s.version          = \"$newVersion\"/" "KlaviyoCore.podspec"

# KlaviyoSwift.podspec - version and dependency
sed -i '' "s/s.version          = \"$currentVersion\"/s.version          = \"$newVersion\"/" "KlaviyoSwift.podspec"
sed -i '' "s/'KlaviyoCore', '~> $currentVersion'/'KlaviyoCore', '~> $newVersion'/" "KlaviyoSwift.podspec"

# KlaviyoForms.podspec - version and dependency
sed -i '' "s/s.version          = \"$currentVersion\"/s.version          = \"$newVersion\"/" "KlaviyoForms.podspec"
sed -i '' "s/'KlaviyoSwift', '~> $currentVersion'/'KlaviyoSwift', '~> $newVersion'/" "KlaviyoForms.podspec"

# KlaviyoSwiftExtension.podspec - version only
sed -i '' "s/s.version          = \"$currentVersion\"/s.version          = \"$newVersion\"/" "KlaviyoSwiftExtension.podspec"

# KlaviyoLocation.podspec - version and dependency (if it exists)
if [[ -f "KlaviyoLocation.podspec" ]]; then
  sed -i '' "s/s.version          = \"$currentVersion\"/s.version          = \"$newVersion\"/" "KlaviyoLocation.podspec"
  sed -i '' "s/'KlaviyoSwift', '~> $currentVersion'/'KlaviyoSwift', '~> $newVersion'/" "KlaviyoLocation.podspec"
fi

# 3. Update test files with hardcoded versions
echo "Updating test files..."

# NetworkSessionTests.swift
sed -i '' "s/klaviyo-swift\/$currentVersion/klaviyo-swift\/$newVersion/g" "Tests/KlaviyoCoreTests/NetworkSessionTests.swift"

# 4. Update test snapshots
echo "Updating test snapshots..."

# Use a simple global replace for version strings in snapshot files
for snapshot in \
  "Tests/KlaviyoCoreTests/__Snapshots__/EncodableTests/testEventPayload.1.json" \
  "Tests/KlaviyoCoreTests/__Snapshots__/EncodableTests/testKlaviyoRequest.1.json" \
  "Tests/KlaviyoCoreTests/__Snapshots__/EncodableTests/testTokenPayload.1.json" \
  "Tests/KlaviyoCoreTests/__Snapshots__/NetworkSessionTests/testCreateEmphemeralSesionHeaders.1.txt" \
  "Tests/KlaviyoCoreTests/__Snapshots__/NetworkSessionTests/testDefaultUserAgent.1.txt" \
  "Tests/KlaviyoSwiftTests/__Snapshots__/EncodableTests/testKlaviyoState.1.json" \
  "Tests/KlaviyoSwiftTests/__Snapshots__/KlaviyoStateTests/testValidStateFileExists.1.txt"
do
  if [[ -f "$snapshot" ]]; then
    sed -i '' "s/$currentVersion/$newVersion/g" "$snapshot"
  fi
done

# 5. Update README.md version references
echo "Updating README.md..."
if [[ -f "README.md" ]]; then
  # Update specific version references (e.g., "SDK version X.Y.Z")
  sed -i '' "s/SDK version $currentVersion/SDK version $newVersion/g" "README.md"
fi

echo ""
echo "✅ Version bumped from $currentVersion to $newVersion"
echo ""
echo "Files updated:"
echo "  - Sources/KlaviyoCore/Utils/Version.swift"
echo "  - KlaviyoCore.podspec"
echo "  - KlaviyoSwift.podspec"
echo "  - KlaviyoForms.podspec"
echo "  - KlaviyoSwiftExtension.podspec"
[[ -f "KlaviyoLocation.podspec" ]] && echo "  - KlaviyoLocation.podspec"
echo "  - Tests/KlaviyoCoreTests/NetworkSessionTests.swift"
echo "  - Test snapshots (7 files)"
echo "  - README.md"
