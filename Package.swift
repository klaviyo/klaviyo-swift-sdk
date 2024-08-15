// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "klaviyo-swift-sdk",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "KlaviyoCore",
            targets: ["KlaviyoCore"]),
        .library(
            name: "KlaviyoSwift",
            targets: ["KlaviyoSwift"]),
        .library(
            name: "KlaviyoSwiftExtension",
            targets: ["KlaviyoSwiftExtension"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
        .package(
            url: "https://github.com/Flight-School/AnyCodable",
            from: "0.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.6.1"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/combine-schedulers", from: "0.9.1")
    ],
    targets: [
        .target(
            name: "KlaviyoCore",
            dependencies: [.product(name: "AnyCodable", package: "AnyCodable")],
            path: "Sources/KlaviyoCore"),
        .testTarget(
            name: "KlaviyoCoreTests",
            dependencies: ["KlaviyoCore"]),
        .target(
            name: "KlaviyoSwift",
            dependencies: [.product(name: "AnyCodable", package: "AnyCodable"), "KlaviyoCore"],
            path: "Sources/KlaviyoSwift",
            resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(
            name: "KlaviyoSwiftTests",
            dependencies: [
                "KlaviyoSwift",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
                "KlaviyoCore"
            ],
            exclude: [
                "__Snapshots__"
            ]),
        .target(
            name: "KlaviyoSwiftExtension",
            dependencies: [],
            path: "Sources/KlaviyoSwiftExtension")
    ])
