// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "klaviyo-swift-sdk",
    platforms: [.iOS(.v15), .macOS(.v10_15)],
    products: [
        .library(
            name: "KlaviyoSwift",
            targets: ["KlaviyoSwift"]),
        .library(
            name: "KlaviyoUI",
            targets: ["KlaviyoUI"]),
        .library(
            name: "KlaviyoSwiftExtension",
            targets: ["KlaviyoSwiftExtension"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
        .package(
            url: "https://github.com/Flight-School/AnyCodable",
            from: "0.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.2"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.5.4"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", from: "1.3.4"),
        .package(url: "https://github.com/pointfreeco/combine-schedulers", from: "1.0.2"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.3.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"601.0.0-prerelease")
    ],
    targets: [
        .target(
            name: "KlaviyoCore",
            dependencies: [.product(name: "AnyCodable", package: "AnyCodable")],
            path: "Sources/KlaviyoCore"),
        .testTarget(
            name: "KlaviyoCoreTests",
            dependencies: [
                "KlaviyoCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "CasePaths", package: "swift-case-paths")
            ]),
        .target(
            name: "KlaviyoSwift",
            dependencies: [
                .product(name: "AnyCodable", package: "AnyCodable"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                "KlaviyoCore",
                "KlaviyoMacros"
            ],
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
        .macro(
            name: "KlaviyoMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]),
        .target(
            name: "KlaviyoUI",
            dependencies: ["KlaviyoSwift"],
            path: "Sources/KlaviyoUI",
            resources: [.process("KlaviyoWebView/Resources")]),
        .testTarget(
            name: "KlaviyoUITests",
            dependencies: [
                "KlaviyoSwift",
                "KlaviyoCore"
            ]),
        .target(
            name: "KlaviyoSwiftExtension",
            dependencies: [],
            path: "Sources/KlaviyoSwiftExtension")
    ])
