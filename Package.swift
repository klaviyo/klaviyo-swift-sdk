// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "klaviyo-swift-sdk",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "KlaviyoSwift",
            targets: ["KlaviyoSwift"]
        ),
        .library(
            name: "KlaviyoForms",
            targets: ["KlaviyoForms"]
        ),
        .library(
            name: "KlaviyoSwiftExtension",
            targets: ["KlaviyoSwiftExtension"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.6.1"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/combine-schedulers", from: "1.0.2"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "KlaviyoCore",
            path: "Sources/KlaviyoCore"
            dependencies: ["KlaviyoSDKDependencies"],
            path: "Sources/KlaviyoCore"
        ),
        .testTarget(
            name: "KlaviyoCoreTests",
            dependencies: [
                "KlaviyoCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                "KlaviyoSDKDependencies"
            ]
        ),
        .target(
            name: "KlaviyoSwift",
            dependencies: [
                "KlaviyoCore",
                "KlaviyoSDKDependencies"
            ],
            path: "Sources/KlaviyoSwift",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
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
            ]
        ),
        .target(
            name: "KlaviyoForms",
            dependencies: ["KlaviyoSwift"],
            path: "Sources/KlaviyoForms",
            resources: [
                .process("InAppForms/Assets"),
                .process("KlaviyoWebView/Resources"),
                .process("KlaviyoWebView/Development Assets/Scripts"),
                .process("KlaviyoWebView/Development Assets/HTML")
            ]
        ),
        .testTarget(
            name: "KlaviyoFormsTests",
            dependencies: [
                "KlaviyoSwift",
                "KlaviyoCore",
                "KlaviyoForms",
                "KlaviyoSDKDependencies"
            ],
            resources: [
                .process("Assets")
            ]
        ),
        .target(
            name: "KlaviyoSwiftExtension",
            dependencies: [],
            path: "Sources/KlaviyoSwiftExtension"
        ),

        // Vendorized Things
        .target(
            name: "KlaviyoSDKDependencies",
            dependencies: [],
            path: "Sources/KlaviyoSDKDependencies"
        )
    ]
)

for target in package.targets {
    target.swiftSettings = target.swiftSettings ?? []
    target.swiftSettings?.append(contentsOf: [
        .enableExperimentalFeature("StrictConcurrency")
    ])
}
