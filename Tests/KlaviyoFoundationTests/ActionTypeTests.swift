//
//  ActionTypeTests.swift
//  klaviyo-swift-sdk
//

import KlaviyoFoundation
import XCTest

final class ActionTypeTests: XCTestCase {
    func testRawValuesMatchThePushPayloadContract() {
        XCTAssertEqual(ActionType.openApp.rawValue, "open_app")
        XCTAssertEqual(ActionType.deepLink.rawValue, "deep_link")
        XCTAssertEqual(ActionType.openUrl.rawValue, "open_url")
    }

    func testKnownRawValuesRoundTrip() {
        XCTAssertEqual(ActionType(rawValue: "open_app"), .openApp)
        XCTAssertEqual(ActionType(rawValue: "deep_link"), .deepLink)
        XCTAssertEqual(ActionType(rawValue: "open_url"), .openUrl)
    }

    func testUnknownOrDifferentlyCasedRawValuesAreNil() {
        for raw in ["", "OPEN_URL", "openUrl", "open-url", "intent"] {
            XCTAssertNil(ActionType(rawValue: raw), "\(raw) must not map to an ActionType")
        }
    }

    func testDisplayNames() {
        XCTAssertEqual(ActionType.openApp.displayName(), "Open App")
        XCTAssertEqual(ActionType.deepLink.displayName(), "Deep Link")
        XCTAssertEqual(ActionType.openUrl.displayName(), "Open URL")
    }
}
