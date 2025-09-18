//
//  DeepLinkHandlingTests.swift
//
//  Created by Cursor AI on 8/11/25.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import Foundation
import XCTest

final class DeepLinkHandlingTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()

        // Ensure clean deep link handler state for each test
        environment.linkHandler.unregisterCustomHandler()

        // Reset TCA state to ensure clean slate for each test
        // This is crucial because previous tests might leave isProcessingDeepLink = true
        klaviyoSwiftEnvironment.state = {
            KlaviyoState(queue: [], requestsInFlight: [])
        }
    }

    @MainActor
    override func tearDown() async throws {
        // Ensure each test cleans up after itself
        environment.linkHandler.unregisterCustomHandler()

        // Reset TCA state to clean slate after each test
        klaviyoSwiftEnvironment.state = {
            KlaviyoState(queue: [], requestsInFlight: [])
        }

        // Reset environments to ensure clean state
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()

        try await super.tearDown()
    }

    @MainActor
    func testOpenDeepLinkActionCallsLinkHandler() async throws {
        let expectedURL = URL(string: "https://example.com/path")!
        let called = expectation(description: "linkHandler.openURL called")
        var handlerCalled = false

        environment.linkHandler.registerCustomHandler { url in
            XCTAssertEqual(url, expectedURL)
            handlerCalled = true
            called.fulfill()
        }

        let store = TestStore(initialState: KlaviyoState(queue: [], requestsInFlight: []), reducer: KlaviyoReducer())

        await store.send(.openDeepLink(expectedURL)) {
            $0.isProcessingDeepLink = true
        }

        await store.receive(.deepLinkProcessingCompleted) {
            $0.isProcessingDeepLink = false
        }

        await fulfillment(of: [called], timeout: 1.0)
        XCTAssertTrue(handlerCalled)
    }

    @MainActor
    func testRegisterDeepLinkHandlerOverridesEnvironmentFallback() async throws {
        let expectedURL = URL(string: "https://example.com/override")!

        let customCalled = expectation(description: "custom handler called")
        KlaviyoSDK().registerDeepLinkHandler { url in
            XCTAssertEqual(url, expectedURL)
            customCalled.fulfill()
        }

        let store = TestStore(initialState: KlaviyoState(queue: [], requestsInFlight: []), reducer: KlaviyoReducer())
        await store.send(.openDeepLink(expectedURL)) {
            $0.isProcessingDeepLink = true
        }

        await store.receive(.deepLinkProcessingCompleted) {
            $0.isProcessingDeepLink = false
        }

        await fulfillment(of: [customCalled], timeout: 1.0)
    }

    @MainActor
    func testHandleNotificationResponseUsesRegisteredDeepLinkHandler() async throws {
        let urlString = "https://example.com/deeplink"
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "url": urlString
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        let handlerCalled = expectation(description: "registered deep link handler called")
        let completionCalled = expectation(description: "completion handler called")

        let sdk = KlaviyoSDK()

        // Verify clean starting state
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered, "Should start with no handler registered")

        // Use the modern approach: register the handler first
        _ = sdk.registerDeepLinkHandler { url in
            XCTAssertEqual(url.absoluteString, urlString)
            handlerCalled.fulfill()
        }

        // Verify the handler was registered
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered, "Handler should be registered")

        let result = sdk.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        })

        XCTAssertTrue(result)
        await fulfillment(of: [handlerCalled, completionCalled], timeout: 1.0)
    }

    @MainActor
    func testHandleNotificationResponseDispatchesOpenDeepLinkWhenNoHandler() async throws {
        let urlString = "https://example.com/deeplink2"
        let expectedURL = try XCTUnwrap(URL(string: urlString))
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "url": urlString
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        // Ensure no custom handler is registered (testing the "no handler" scenario)
        environment.linkHandler.unregisterCustomHandler()
        XCTAssertFalse(environment.linkHandler.hasCustomHandler, "Should have no custom handler registered")

        let completionCalled = expectation(description: "completion handler called")

        // Set up action tracking through the test environment
        let actionReceived = expectation(description: "openDeepLink action received")
        let originalSend = klaviyoSwiftEnvironment.send
        klaviyoSwiftEnvironment.send = { action in
            if case let .openDeepLink(url) = action {
                XCTAssertEqual(url, expectedURL, "Should dispatch openDeepLink with correct URL")
                actionReceived.fulfill()

                // Return nil to prevent the actual async processing that could interfere
                // This test is only verifying that the action is dispatched, not the full processing
                return nil
            }
            return originalSend(action)
        }

        let sdk = KlaviyoSDK()
        let result = sdk.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        })

        // Verify the notification was processed successfully
        XCTAssertTrue(result, "SDK should return true for Klaviyo notifications with deep links")

        // Verify that both the completion handler was called AND the deep link action was dispatched
        await fulfillment(of: [completionCalled, actionReceived], timeout: 1.0)

        // Restore original send function
        klaviyoSwiftEnvironment.send = originalSend
    }
}
