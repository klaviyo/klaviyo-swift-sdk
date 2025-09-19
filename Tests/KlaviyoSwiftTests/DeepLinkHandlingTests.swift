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

    // MARK: - TCA State Management Tests

    @MainActor
    func testOpenDeepLinkActionSetsProcessingState() async throws {
        let url = URL(string: "https://example.com/test")!
        let store = TestStore(initialState: KlaviyoState(queue: [], requestsInFlight: []), reducer: KlaviyoReducer())

        environment.linkHandler.registerCustomHandler { _ in }

        await store.send(.openDeepLink(url)) {
            $0.isProcessingDeepLink = true
        }

        await store.receive(.deepLinkProcessingCompleted) {
            $0.isProcessingDeepLink = false
        }
    }

    @MainActor
    func testOpenDeepLinkActionIgnoredWhenAlreadyProcessing() async throws {
        let url = URL(string: "https://example.com/test")!
        var initialState = KlaviyoState(queue: [], requestsInFlight: [])
        initialState.isProcessingDeepLink = true

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.openDeepLink(url))
    }

    @MainActor
    func testDeepLinkProcessingCompletedResetsState() async throws {
        var initialState = KlaviyoState(queue: [], requestsInFlight: [])
        initialState.isProcessingDeepLink = true

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.deepLinkProcessingCompleted) {
            $0.isProcessingDeepLink = false
        }
    }

    @MainActor
    func testSequentialDeepLinkProcessing() async throws {
        let url1 = URL(string: "https://example.com/test1")!
        let url2 = URL(string: "https://example.com/test2")!

        let store = TestStore(initialState: KlaviyoState(queue: [], requestsInFlight: []), reducer: KlaviyoReducer())

        // Register a simple handler
        environment.linkHandler.registerCustomHandler { _ in }

        // Send first action - should be processed
        await store.send(.openDeepLink(url1)) {
            $0.isProcessingDeepLink = true
        }

        // Complete first processing
        await store.receive(.deepLinkProcessingCompleted) {
            $0.isProcessingDeepLink = false
        }

        // Now that processing is complete, a new action should work
        await store.send(.openDeepLink(url2)) {
            $0.isProcessingDeepLink = true
        }

        await store.receive(.deepLinkProcessingCompleted) {
            $0.isProcessingDeepLink = false
        }
    }

    // MARK: - isDeepLinkHandlerRegistered Property Tests

    @MainActor
    func testIsDeepLinkHandlerRegisteredProperty() {
        let sdk = KlaviyoSDK()

        // Initial state should be false
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)

        // After registering a handler
        sdk.registerDeepLinkHandler { _ in }
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered)

        // After unregistering the handler
        sdk.unregisterDeepLinkHandler()
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)
    }

    @MainActor
    func testIsDeepLinkHandlerRegisteredWithMultipleInstances() {
        let sdk1 = KlaviyoSDK()
        let sdk2 = KlaviyoSDK()

        // Both should start as false
        XCTAssertFalse(sdk1.isDeepLinkHandlerRegistered)
        XCTAssertFalse(sdk2.isDeepLinkHandlerRegistered)

        // Register handler on first instance
        _ = sdk1.registerDeepLinkHandler { _ in }

        // Both should reflect the same underlying state (shared environment)
        XCTAssertTrue(sdk1.isDeepLinkHandlerRegistered)
        XCTAssertTrue(sdk2.isDeepLinkHandlerRegistered)
    }

    @MainActor
    func testIsDeepLinkHandlerRegisteredAfterEnvironmentReset() {
        let sdk = KlaviyoSDK()

        // Register a handler
        _ = sdk.registerDeepLinkHandler { _ in }
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered)

        // Reset the environment (simulating what happens in test tearDown)
        environment.linkHandler.unregisterCustomHandler()

        // SDK should reflect the new state
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)
    }

    @MainActor
    func testIsDeepLinkHandlerRegisteredConsistencyWithEnvironment() {
        let sdk = KlaviyoSDK()

        // Should match environment state
        XCTAssertEqual(sdk.isDeepLinkHandlerRegistered, environment.linkHandler.hasCustomHandler)

        // Register through SDK
        _ = sdk.registerDeepLinkHandler { _ in }
        XCTAssertEqual(sdk.isDeepLinkHandlerRegistered, environment.linkHandler.hasCustomHandler)
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered)

        // Unregister through environment directly
        environment.linkHandler.unregisterCustomHandler()
        XCTAssertEqual(sdk.isDeepLinkHandlerRegistered, environment.linkHandler.hasCustomHandler)
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)
    }
}
