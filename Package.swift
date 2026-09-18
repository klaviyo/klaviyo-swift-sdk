// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "klaviyo-swift-sdk",
    platforms: [.iOS(.v13)],
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
        ),
        .library(
            name: "KlaviyoLocation",
            targets: ["KlaviyoLocation"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
        .package(
            url: "https://github.com/Flight-School/AnyCodable",
            from: "0.6.0"
        )
    ],
    targets: [
        .target(
            name: "KlaviyoAutomaticPushBootstrap",
            path: "Sources/KlaviyoAutomaticPushBootstrap",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("UIKit")]
        ),
        .target(
            name: "KlaviyoCore",
            dependencies: [
                .product(name: "AnyCodable", package: "AnyCodable")
            ],
            path: "Sources/KlaviyoCore"
        ),
        .testTarget(
            name: "KlaviyoCoreTests",
            dependencies: [
                "KlaviyoCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        ),
        .target(
            name: "KlaviyoSwift",
            dependencies: [
                .product(name: "AnyCodable", package: "AnyCodable"),
                "KlaviyoCore",
                "KlaviyoAutomaticPushBootstrap"
            ],
            path: "Sources/KlaviyoSwift",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "KlaviyoSwiftTests",
            dependencies: [
                "KlaviyoSwift",
                "KlaviyoCore",
                "KlaviyoAutomaticPushBootstrap"
            ]
        ),
        .target(
            name: "KlaviyoForms",
            dependencies: ["KlaviyoCore"],
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
                "KlaviyoForms"
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
        .testTarget(
            name: "KlaviyoSwiftExtensionTests",
            dependencies: [
                "KlaviyoSwiftExtension",
                // Test-only: lets the allowlist parity test compare against the KlaviyoCore copy.
                "KlaviyoCore"
            ]
        ),
        .target(
            name: "KlaviyoLocation",
            dependencies: [
                "KlaviyoSwift",
                "KlaviyoCore"
            ]
        ),
        .testTarget(
            name: "KlaviyoLocationTests",
            dependencies: [
                "KlaviyoSwift",
                "KlaviyoCore",
                "KlaviyoLocation"
            ]
        )
    ]
)
