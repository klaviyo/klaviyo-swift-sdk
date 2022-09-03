// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "klaviyo-swift-sdk",
    platforms: [.iOS(.v13),],
    products: [
        .library(
            name: "KlaviyoSwift",
            targets: ["KlaviyoSwift"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "KlaviyoSwift",
            dependencies: []),
        .testTarget(
            name: "KlaviyoSwiftTests",
            dependencies: ["KlaviyoSwift"]),
    ]
)
