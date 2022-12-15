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
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
        .package(
            url: "https://github.com/Flight-School/AnyCodable",
            from: "0.6.0"
        ),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.6.1"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "KlaviyoSwift",
            dependencies: [.product(name: "AnyCodable", package: "AnyCodable")]),
        .testTarget(
            name: "KlaviyoSwiftTests",
            dependencies: [
                "KlaviyoSwift",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "CasePaths", package: "swift-case-paths"),
            ],
            exclude: [
              "__Snapshots__"
            ]
        ),
    ]
)
