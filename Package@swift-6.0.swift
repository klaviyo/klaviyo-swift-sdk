// swift-tools-version:6.0

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
        .package(url: "https://github.com/pointfreeco/combine-schedulers", from: "1.0.2"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "KlaviyoCore",
            dependencies: ["KlaviyoSDKDependencies"],
            path: "Sources/KlaviyoCore"),
        .testTarget(
            name: "KlaviyoCoreTests",
            dependencies: [
                "KlaviyoCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                "KlaviyoSDKDependencies"
            ]),
        .target(
            name: "KlaviyoSwift",
            dependencies: [
                "KlaviyoSDKDependencies",
                "KlaviyoCore"
            ],
            path: "Sources/KlaviyoSwift",
            resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(
            name: "KlaviyoSwiftTests",
            dependencies: [
                "KlaviyoSwift",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                "KlaviyoSDKDependencies",
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
                "KlaviyoCore",
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay")
            ],
            exclude: [
                "__Snapshots__"
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
                "KlaviyoCore",
                "KlaviyoSDKDependencies"
            ]),
        .target(
            name: "KlaviyoSwiftExtension",
            dependencies: [],
            path: "Sources/KlaviyoSwiftExtension"),

        // Vendorized Things
        .target(
            name: "KlaviyoSDKDependencies",
            dependencies: [],
            path: "Sources/KlaviyoSDKDependencies")
    ],
    swiftLanguageModes: [.v6])
