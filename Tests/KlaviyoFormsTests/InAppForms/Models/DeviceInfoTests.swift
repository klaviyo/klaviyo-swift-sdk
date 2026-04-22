//
//  DeviceInfoTests.swift
//  klaviyo-swift-sdk
//
//  Created by Evan Masseau on 4/22/26.
//

@testable import KlaviyoForms
import UIKit
import XCTest

final class DeviceInfoTests: XCTestCase {
    // MARK: - Serialization shape

    func testSerializationMatchesDocumentedShape() throws {
        let info = DeviceInfo(
            screen: .init(width: 402, height: 874),
            safeAreaInsets: .init(top: 47, bottom: 34, left: 0, right: 0),
            orientation: "portrait-primary",
            dpr: 3
        )

        let json = info.toJsonString()
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let screen = try XCTUnwrap(parsed["screen"] as? [String: Any])
        XCTAssertEqual(screen["width"] as? Int, 402)
        XCTAssertEqual(screen["height"] as? Int, 874)

        let insets = try XCTUnwrap(parsed["safeAreaInsets"] as? [String: Any])
        XCTAssertEqual(insets["top"] as? Int, 47)
        XCTAssertEqual(insets["bottom"] as? Int, 34)
        XCTAssertEqual(insets["left"] as? Int, 0)
        XCTAssertEqual(insets["right"] as? Int, 0)

        XCTAssertEqual(parsed["orientation"] as? String, "portrait-primary")
        XCTAssertEqual(parsed["dpr"] as? Int, 3)
    }

    // MARK: - Orientation mapping

    func testOrientationMappingCoversAllCSSOMLabels() {
        XCTAssertEqual(DeviceInfo.cssOrientation(for: .portrait), "portrait-primary")
        XCTAssertEqual(DeviceInfo.cssOrientation(for: .portraitUpsideDown), "portrait-secondary")
        XCTAssertEqual(DeviceInfo.cssOrientation(for: .landscapeLeft), "landscape-primary")
        XCTAssertEqual(DeviceInfo.cssOrientation(for: .landscapeRight), "landscape-secondary")
        XCTAssertEqual(DeviceInfo.cssOrientation(for: .unknown), "portrait-primary")
    }

    // MARK: - Screen + insets at various native scales

    func testMakeAtNativeScale2() {
        let info = DeviceInfo.make(
            screenBounds: CGSize(width: 390, height: 844),
            orientation: .portrait,
            nativeScale: 2,
            safeAreaInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        )

        XCTAssertEqual(info.screen.width, 390)
        XCTAssertEqual(info.screen.height, 844)
        XCTAssertEqual(info.safeAreaInsets.top, 47)
        XCTAssertEqual(info.safeAreaInsets.bottom, 34)
        XCTAssertEqual(info.dpr, 2)
        XCTAssertEqual(info.orientation, "portrait-primary")
    }

    func testMakeAtNativeScale3() {
        let info = DeviceInfo.make(
            screenBounds: CGSize(width: 402, height: 874),
            orientation: .portrait,
            nativeScale: 3,
            safeAreaInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        )

        XCTAssertEqual(info.screen.width, 402)
        XCTAssertEqual(info.screen.height, 874)
        XCTAssertEqual(info.dpr, 3)
    }

    func testMakeSwapsDimensionsWhenBoundsDoNotMatchOrientation() {
        // Simulate UIKit reporting natural (portrait) bounds while interface is landscape.
        let info = DeviceInfo.make(
            screenBounds: CGSize(width: 402, height: 874),
            orientation: .landscapeLeft,
            nativeScale: 3,
            safeAreaInsets: .zero
        )

        XCTAssertEqual(info.screen.width, 874)
        XCTAssertEqual(info.screen.height, 402)
        XCTAssertEqual(info.orientation, "landscape-primary")
    }

    // MARK: - JS escaping

    func testJsEscapingHandlesBackslashesAndSingleQuotes() {
        let payload = "it's a back\\slash"
        XCTAssertEqual(payload.klaviyoJsSingleQuoteEscaped, "it\\'s a back\\\\slash")
    }

    func testJsEscapingLeavesDoubleQuotesUntouched() {
        // JSON's own double-quote syntax must survive embedding in a single-quoted
        // JS string literal — otherwise onsite will see a broken payload.
        let payload = "{\"screen\":{\"width\":402}}"
        XCTAssertEqual(payload.klaviyoJsSingleQuoteEscaped, payload)
    }

    func testEndToEndJsEscapedPayloadIsSingleQuoteSafe() {
        let info = DeviceInfo(
            screen: .init(width: 402, height: 874),
            safeAreaInsets: .init(top: 47, bottom: 34, left: 0, right: 0),
            orientation: "portrait-primary",
            dpr: 3
        )
        let escaped = info.toJsonString().klaviyoJsSingleQuoteEscaped
        // The escaped payload must be safely embeddable inside `'...'` JS literal.
        XCTAssertFalse(escaped.contains("'"), "unescaped single quote in payload")
    }
}
