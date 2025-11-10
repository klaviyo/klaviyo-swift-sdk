//
//  DeepLinkHandlerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Claude on 9/17/25.
//

@testable import KlaviyoCore
import XCTest

final class DeepLinkHandlerTests: XCTestCase {
    var deepLinkHandler: DeepLinkHandler!

    override func setUp() {
        super.setUp()
        deepLinkHandler = DeepLinkHandler()
    }

    override func tearDown() {
        deepLinkHandler.unregisterCustomHandler()
        deepLinkHandler = nil
        super.tearDown()
    }

    // MARK: - Custom Handler Registration Tests

    func testRegisterCustomHandler() {
        XCTAssertFalse(deepLinkHandler.hasCustomHandler)

        deepLinkHandler.registerCustomHandler { _ in }

        XCTAssertTrue(deepLinkHandler.hasCustomHandler)
    }

    func testUnregisterCustomHandler() {
        deepLinkHandler.registerCustomHandler { _ in }
        XCTAssertTrue(deepLinkHandler.hasCustomHandler)

        deepLinkHandler.unregisterCustomHandler()

        XCTAssertFalse(deepLinkHandler.hasCustomHandler)
    }

    func testUnregisterCustomHandlerWhenNoneRegistered() {
        XCTAssertFalse(deepLinkHandler.hasCustomHandler)

        // Should not crash or cause issues
        deepLinkHandler.unregisterCustomHandler()

        XCTAssertFalse(deepLinkHandler.hasCustomHandler)
    }

    // MARK: - Custom Handler Execution Tests

    @MainActor
    func testOpenURLUsesCustomHandlerWhenRegistered() async {
        let expectedURL = URL(string: "https://example.com/custom")!
        let handlerCalled = expectation(description: "custom handler called")

        deepLinkHandler.registerCustomHandler { url in
            XCTAssertEqual(url, expectedURL)
            handlerCalled.fulfill()
        }

        await deepLinkHandler.openURL(expectedURL)
        await fulfillment(of: [handlerCalled], timeout: 1.0)
    }

    // MARK: - Handler Replacement Tests

    @MainActor
    func testRegisteringNewHandlerReplacesOld() async {
        let url = URL(string: "https://example.com/test")!
        let firstHandlerCalled = expectation(description: "first handler called")
        let secondHandlerCalled = expectation(description: "second handler called")
        firstHandlerCalled.isInverted = true

        // Register first handler
        deepLinkHandler.registerCustomHandler { _ in
            firstHandlerCalled.fulfill()
        }

        // Register second handler (should replace first)
        deepLinkHandler.registerCustomHandler { receivedURL in
            XCTAssertEqual(receivedURL, url)
            secondHandlerCalled.fulfill()
        }

        await deepLinkHandler.openURL(url)

        await fulfillment(of: [firstHandlerCalled, secondHandlerCalled], timeout: 1.0)
    }

    // MARK: - Thread Safety Tests

    @MainActor
    func testCustomHandlerCalledOnMainActor() async {
        let url = URL(string: "https://example.com/main-actor")!
        let handlerCalled = expectation(description: "handler called on main actor")

        deepLinkHandler.registerCustomHandler { _ in
            XCTAssertTrue(Thread.isMainThread, "Custom handler should be called on main thread")
            handlerCalled.fulfill()
        }

        await deepLinkHandler.openURL(url)
        await fulfillment(of: [handlerCalled], timeout: 1.0)
    }
}
