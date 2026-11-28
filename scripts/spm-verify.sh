#!/usr/bin/env bash
# Resolves and builds a published klaviyo-swift-sdk tag as an SPM dependency for iOS Simulator.
# Usage: scripts/spm-verify.sh <tag> [work-dir]
set -euo pipefail

TAG="${1:?usage: spm-verify.sh <tag> [work-dir]}"
WORK_DIR="${2:-$(mktemp -d)}"
REPO_URL="${SPM_VERIFY_REPO_URL:-https://github.com/klaviyo/klaviyo-swift-sdk}"
PRODUCTS=(KlaviyoSwift KlaviyoForms KlaviyoSwiftExtension KlaviyoLocation)

mkdir -p "$WORK_DIR/Sources/SPMVerify"
cd "$WORK_DIR"

product_deps=""
imports=""
for product in "${PRODUCTS[@]}"; do
  product_deps+="                .product(name: \"$product\", package: \"klaviyo-swift-sdk\"),"$'\n'
  imports+="import $product"$'\n'
done

cat > Package.swift <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPMVerify",
    platforms: [.iOS(.v13)],
    products: [.library(name: "SPMVerify", targets: ["SPMVerify"])],
    dependencies: [
        .package(url: "$REPO_URL", exact: "$TAG")
    ],
    targets: [
        .target(
            name: "SPMVerify",
            dependencies: [
$product_deps            ]
        )
    ]
)
EOF

printf '%s' "$imports" > Sources/SPMVerify/SPMVerify.swift

echo "::group::Package.swift"
cat Package.swift
echo "::endgroup::"

echo "::group::swift package resolve"
swift package resolve
echo "::endgroup::"

echo "::group::xcodebuild (iOS Simulator)"
xcodebuild build \
  -scheme SPMVerify \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO
echo "::endgroup::"

echo "✅ klaviyo-swift-sdk $TAG resolved and built for iOS Simulator"
