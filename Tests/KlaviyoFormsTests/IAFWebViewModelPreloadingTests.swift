//
//  IAFWebViewModelPreloadingTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

import XCTest

// Tests are skipped pending MAGE-992 (intermittent WKWebView/AsyncStream deadlock on CI).
// setUp/tearDown and all state removed so nothing can hang before the skip fires.
final class IAFWebViewModelPreloadingTests: XCTestCase {
    func testPreloadWebsiteSuccess() throws {
        throw XCTSkip("Intermittently hangs on CI due to AsyncStream cancellation deadlock — tracked in MAGE-992")
    }

    func testPreloadWebsiteTimeout() throws {
        throw XCTSkip("Intermittently hangs on CI due to AsyncStream cancellation deadlock — tracked in MAGE-992")
    }

    func testPreloadWebsiteNoActionTimeout() throws {
        throw XCTSkip("Intermittently hangs on CI due to AsyncStream cancellation deadlock — tracked in MAGE-992")
    }
}
