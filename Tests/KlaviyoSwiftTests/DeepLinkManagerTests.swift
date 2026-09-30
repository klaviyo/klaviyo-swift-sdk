//
//  DeepLinkManagerTests.swift
//
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

@MainActor
final class DeepLinkManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        environment.linkHandler.unregisterCustomHandler()
        DeepLinkManager.resetToProduction()
    }

    override func tearDown() {
        DeepLinkManager.resetToProduction()
        environment.linkHandler.unregisterCustomHandler()
        super.tearDown()
    }

    // MARK: - openDeepLink

    func testOpenDeepLink_routesThroughLinkHandler() async {
        let expectedURL = URL(string: "https://example.com/path")!
        let called = expectation(description: "linkHandler.openURL called")
        environment.linkHandler.registerCustomHandler { url in
            XCTAssertEqual(url, expectedURL)
            called.fulfill()
        }

        await DeepLinkManager.openDeepLink(expectedURL)

        await fulfillment(of: [called], timeout: 1.0)
    }

    /// Two opens created in the same main-actor turn must both reach the handler.
    /// The removed reentrancy guard dropped the second one every time in this
    /// arrangement, because the first open set its flag and suspended before the
    /// second was drained. Do not set any state by hand here: overlapping the
    /// real calls is the whole point of the test.
    func testOpenDeepLink_overlappingOpensBothDelivered() async {
        var opened: [URL] = []
        let both = expectation(description: "both deep links delivered")
        both.expectedFulfillmentCount = 2
        environment.linkHandler.registerCustomHandler { url in
            opened.append(url)
            both.fulfill()
        }
        let url1 = URL(string: "https://example.com/1")!
        let url2 = URL(string: "https://example.com/2")!

        async let first: Void = DeepLinkManager.openDeepLink(url1)
        async let second: Void = DeepLinkManager.openDeepLink(url2)
        _ = await (first, second)

        await fulfillment(of: [both], timeout: 1.0)
        XCTAssertEqual(Set(opened), [url1, url2], "neither overlapping open may be dropped")
    }

    func testOpenDeepLink_sequentialCallsBothProcessed() async {
        var opened: [URL] = []
        environment.linkHandler.registerCustomHandler { opened.append($0) }
        let url1 = URL(string: "https://example.com/1")!
        let url2 = URL(string: "https://example.com/2")!

        await DeepLinkManager.openDeepLink(url1)
        await DeepLinkManager.openDeepLink(url2)

        XCTAssertEqual(opened, [url1, url2], "each open should proceed once the previous finished")
    }

    func testOpenDeepLink_withSpy_bypassesProductionPath() async {
        var spiedURL: URL?
        DeepLinkManager.openDeepLinkSpy = { spiedURL = $0 }
        var handlerCalled = false
        environment.linkHandler.registerCustomHandler { _ in handlerCalled = true }

        await DeepLinkManager.openDeepLink(URL(string: "https://example.com/x")!)

        XCTAssertEqual(spiedURL?.absoluteString, "https://example.com/x", "spy should receive the URL")
        XCTAssertFalse(handlerCalled, "production path must be bypassed when a spy is installed")
    }

    // MARK: - resetToProduction

    func testResetToProduction_clearsSpies() {
        DeepLinkManager.openDeepLinkSpy = { _ in }
        DeepLinkManager.openExternalURLSpy = { _ in }

        DeepLinkManager.resetToProduction()

        XCTAssertNil(DeepLinkManager.openDeepLinkSpy)
        XCTAssertNil(DeepLinkManager.openExternalURLSpy)
    }
}
