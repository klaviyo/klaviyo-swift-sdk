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

        // Ensure clean deep link handler + coordinator state for each test.
        environment.linkHandler.unregisterCustomHandler()
        DeepLinkManager.resetToProduction()
    }

    @MainActor
    override func tearDown() async throws {
        environment.linkHandler.unregisterCustomHandler()
        DeepLinkManager.resetToProduction()

        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()

        try await super.tearDown()
    }

    // MARK: - handle(notificationResponse:) → DeepLinkManager

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
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered, "Should start with no handler registered")

        _ = sdk.registerDeepLinkHandler { url in
            XCTAssertEqual(url.absoluteString, urlString)
            handlerCalled.fulfill()
        }
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered, "Handler should be registered")

        let result = sdk.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        })

        XCTAssertTrue(result)
        await fulfillment(of: [handlerCalled, completionCalled], timeout: 1.0)
    }

    @MainActor
    func testHandleNotificationResponseInvokesDeepLinkManagerWhenNoHandler() async throws {
        let urlString = "https://example.com/deeplink2"
        let expectedURL = try XCTUnwrap(URL(string: urlString))
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "url": urlString
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        // No custom handler registered — the facade should route the URL to DeepLinkManager.
        environment.linkHandler.unregisterCustomHandler()

        let completionCalled = expectation(description: "completion handler called")
        let deepLinkInvoked = expectation(description: "DeepLinkManager.openDeepLink invoked")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, expectedURL, "Should invoke openDeepLink with the notification's URL")
            deepLinkInvoked.fulfill()
        }

        let sdk = KlaviyoSDK()
        let result = sdk.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        })

        XCTAssertTrue(result, "SDK should return true for Klaviyo notifications with deep links")
        await fulfillment(of: [completionCalled, deepLinkInvoked], timeout: 1.0)
    }

    // MARK: - open_url with allowlisted non-web schemes

    @MainActor
    func testHandleNotificationResponseDispatchesOpenWebUrlForMailtoWebUrl() async throws {
        let urlString = "mailto:support@example.com"
        let expectedURL = try XCTUnwrap(URL(string: urlString))
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "web_url": urlString
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        environment.linkHandler.unregisterCustomHandler()

        let completionCalled = expectation(description: "completion handler called")
        let externalUrlInvoked = expectation(description: "DeepLinkManager.openExternalURL invoked for mailto:")
        DeepLinkManager.openExternalURLSpy = { url in
            XCTAssertEqual(url, expectedURL, "Should invoke openExternalURL with mailto: URL")
            externalUrlInvoked.fulfill()
        }

        let klaviyoSDK = KlaviyoSDK()
        let result = klaviyoSDK.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        })

        XCTAssertTrue(result, "SDK should return true for Klaviyo notifications with web_url")
        await fulfillment(of: [completionCalled, externalUrlInvoked], timeout: 1.0)
    }

    @MainActor
    func testHandleNotificationResponseDispatchesOpenWebUrlForTelWebUrl() async throws {
        let urlString = "tel:+15551234567"
        let expectedURL = try XCTUnwrap(URL(string: urlString))
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "web_url": urlString
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        environment.linkHandler.unregisterCustomHandler()

        let completionCalled = expectation(description: "completion handler called")
        let externalUrlInvoked = expectation(description: "DeepLinkManager.openExternalURL invoked for tel:")
        DeepLinkManager.openExternalURLSpy = { url in
            XCTAssertEqual(url, expectedURL, "Should invoke openExternalURL with tel: URL")
            externalUrlInvoked.fulfill()
        }

        let klaviyoSDK = KlaviyoSDK()
        let result = klaviyoSDK.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        })

        XCTAssertTrue(result, "SDK should return true for Klaviyo notifications with web_url")
        await fulfillment(of: [completionCalled, externalUrlInvoked], timeout: 1.0)
    }

    @MainActor
    func testHandleNotificationResponseDropsBlockedSchemeWebUrl() throws {
        // javascript: is a blocked scheme — the gate is the synchronous klaviyoWebUrl
        // property, and resolveOpenAction only calls openExternalURL when it is non-nil
        // (positive dispatch coverage in the mailto:/tel: tests above). handle still
        // returns true: it is a valid Klaviyo notification, it just takes no open action.
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "web_url": "javascript:alert(1)"
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        environment.linkHandler.unregisterCustomHandler()

        XCTAssertNil(response.klaviyoWebUrl, "Blocked scheme must not produce a web URL")

        let klaviyoSDK = KlaviyoSDK()
        let result = klaviyoSDK.handle(notificationResponse: response, withCompletionHandler: {})
        XCTAssertTrue(result, "Klaviyo notification is still handled; it just takes no open action")
    }

    // MARK: - isDeepLinkHandlerRegistered Property Tests

    @MainActor
    func testIsDeepLinkHandlerRegisteredProperty() {
        let sdk = KlaviyoSDK()

        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)

        sdk.registerDeepLinkHandler { _ in }
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered)

        sdk.unregisterDeepLinkHandler()
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)
    }

    @MainActor
    func testIsDeepLinkHandlerRegisteredWithMultipleInstances() {
        let sdk1 = KlaviyoSDK()
        let sdk2 = KlaviyoSDK()

        XCTAssertFalse(sdk1.isDeepLinkHandlerRegistered)
        XCTAssertFalse(sdk2.isDeepLinkHandlerRegistered)

        _ = sdk1.registerDeepLinkHandler { _ in }

        // Both should reflect the same underlying state (shared environment).
        XCTAssertTrue(sdk1.isDeepLinkHandlerRegistered)
        XCTAssertTrue(sdk2.isDeepLinkHandlerRegistered)
    }

    @MainActor
    func testIsDeepLinkHandlerRegisteredAfterEnvironmentReset() {
        let sdk = KlaviyoSDK()

        _ = sdk.registerDeepLinkHandler { _ in }
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered)

        environment.linkHandler.unregisterCustomHandler()

        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)
    }

    @MainActor
    func testIsDeepLinkHandlerRegisteredConsistencyWithEnvironment() {
        let sdk = KlaviyoSDK()

        XCTAssertEqual(sdk.isDeepLinkHandlerRegistered, environment.linkHandler.hasCustomHandler)

        _ = sdk.registerDeepLinkHandler { _ in }
        XCTAssertEqual(sdk.isDeepLinkHandlerRegistered, environment.linkHandler.hasCustomHandler)
        XCTAssertTrue(sdk.isDeepLinkHandlerRegistered)

        environment.linkHandler.unregisterCustomHandler()
        XCTAssertEqual(sdk.isDeepLinkHandlerRegistered, environment.linkHandler.hasCustomHandler)
        XCTAssertFalse(sdk.isDeepLinkHandlerRegistered)
    }
}
