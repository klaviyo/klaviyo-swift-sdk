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
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink, "processing flag should reset after opening")
    }

    func testOpenDeepLink_skippedWhenAlreadyProcessing() async {
        DeepLinkManager.isProcessingDeepLink = true
        var handlerCalled = false
        environment.linkHandler.registerCustomHandler { _ in handlerCalled = true }

        await DeepLinkManager.openDeepLink(URL(string: "https://example.com")!)

        XCTAssertFalse(handlerCalled, "openURL must not run while a deep link is already processing")
        XCTAssertTrue(DeepLinkManager.isProcessingDeepLink, "the in-flight processing state must be left untouched")
    }

    func testOpenDeepLink_sequentialCallsBothProcessed() async {
        var opened: [URL] = []
        environment.linkHandler.registerCustomHandler { opened.append($0) }
        let url1 = URL(string: "https://example.com/1")!
        let url2 = URL(string: "https://example.com/2")!

        await DeepLinkManager.openDeepLink(url1)
        await DeepLinkManager.openDeepLink(url2)

        XCTAssertEqual(opened, [url1, url2], "each open should proceed once the previous finished")
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink)
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

    func testResetToProduction_clearsSpyAndFlag() {
        DeepLinkManager.openDeepLinkSpy = { _ in }
        DeepLinkManager.isProcessingDeepLink = true

        DeepLinkManager.resetToProduction()

        XCTAssertNil(DeepLinkManager.openDeepLinkSpy)
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink)
    }
}
