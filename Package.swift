// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "klaviyo-swift-sdk",
    platforms: [.iOS(v13)],
    products: [
        .library(
            name: "klaviyo-swift-sdk",
            targets: ["klaviyo-swift-sdk"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "klaviyo-swift-sdk",
            dependencies: []),
        .testTarget(
            name: "klaviyo-swift-sdkTests",
            dependencies: ["klaviyo-swift-sdk"]),
    ]
)
