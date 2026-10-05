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
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

    // MARK: - openDeepLink

    func testOpenDeepLink_routesThroughLinkHandler() async throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://example.com/path"))
        let called = expectation(description: "linkHandler.openURL called")
        environment.linkHandler.registerCustomHandler { url in
            XCTAssertEqual(url, expectedURL)
            called.fulfill()
        }

        await DeepLinkManager.openDeepLink(expectedURL)

        await fulfillment(of: [called], timeout: 1.0)
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink)
    }

    /// Hold a system open pending and verify an overlapping request is skipped.
    /// The barrier makes the overlap independent of task scheduling.
    func testOpenDeepLink_skipsOverlapAndAcceptsRequestAfterCompletion() async throws {
        let url1 = try XCTUnwrap(URL(string: "abcdcompany://notifications?request=1"))
        let url2 = try XCTUnwrap(URL(string: "abcdcompany://notifications?request=2"))
        var opened: [URL] = []
        var finishFirst: CheckedContinuation<Bool, Never>?
        var firstCompleted = false
        let firstStarted = expectation(description: "first system open is suspended")
        environment.linkHandler = DeepLinkHandler { url in
            opened.append(url)
            if url == url1 {
                return await withCheckedContinuation { continuation in
                    finishFirst = continuation
                    firstStarted.fulfill()
                }
            }
            return true
        }

        let first = Task {
            await DeepLinkManager.openDeepLink(url1)
            firstCompleted = true
        }
        await fulfillment(of: [firstStarted], timeout: 1.0)
        XCTAssertNotNil(finishFirst, "the first request must reach the suspension barrier")
        await DeepLinkManager.openDeepLink(url2)

        XCTAssertFalse(firstCompleted, "the first open must still be pending when the second arrives")
        XCTAssertEqual(opened, [url1], "an overlapping open must be skipped")
        XCTAssertTrue(DeepLinkManager.isProcessingDeepLink, "the first request must retain the busy flag")

        finishFirst?.resume(returning: true)
        await first.value
        XCTAssertTrue(firstCompleted)
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink)

        await DeepLinkManager.openDeepLink(url2)
        XCTAssertEqual(opened, [url1, url2], "a new request must proceed after the first finishes")
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink)
    }

    func testOpenDeepLink_sequentialCallsBothProcessed() async throws {
        var opened: [URL] = []
        environment.linkHandler.registerCustomHandler { opened.append($0) }
        let url1 = try XCTUnwrap(URL(string: "https://example.com/1"))
        let url2 = try XCTUnwrap(URL(string: "https://example.com/2"))

        await DeepLinkManager.openDeepLink(url1)
        await DeepLinkManager.openDeepLink(url2)

        XCTAssertEqual(opened, [url1, url2], "each open should proceed once the previous finished")
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink)
    }

    func testOpenDeepLink_withSpy_bypassesProductionPath() async throws {
        var spiedURL: URL?
        DeepLinkManager.openDeepLinkSpy = { spiedURL = $0 }
        var handlerCalled = false
        environment.linkHandler.registerCustomHandler { _ in handlerCalled = true }

        try await DeepLinkManager.openDeepLink(XCTUnwrap(URL(string: "https://example.com/x")))

        XCTAssertEqual(spiedURL?.absoluteString, "https://example.com/x", "spy should receive the URL")
        XCTAssertFalse(handlerCalled, "production path must be bypassed when a spy is installed")
    }

    // MARK: - resetToProduction

    func testResetToProduction_clearsSpiesAndFlag() {
        DeepLinkManager.openDeepLinkSpy = { _ in }
        DeepLinkManager.openExternalURLSpy = { _ in }
        DeepLinkManager.isProcessingDeepLink = true

        DeepLinkManager.resetToProduction()

        XCTAssertNil(DeepLinkManager.openDeepLinkSpy)
        XCTAssertNil(DeepLinkManager.openExternalURLSpy)
        XCTAssertFalse(DeepLinkManager.isProcessingDeepLink)
    }
}
