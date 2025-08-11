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
    }

    @MainActor
    func testOpenDeepLinkActionCallsEnvironmentOpenURL() async throws {
        let expectedURL = URL(string: "https://example.com/path")!
        let called = expectation(description: "environment.openURL called")

        environment.openURL = { url in
            XCTAssertEqual(url, expectedURL)
            called.fulfill()
        }

        let store = TestStore(initialState: KlaviyoState(queue: [], requestsInFlight: []), reducer: KlaviyoReducer())

        _ = await store.send(.openDeepLink(expectedURL))
        await fulfillment(of: [called], timeout: 1.0)
    }

    @MainActor
    func testRegisterDeepLinkHandlerOverridesEnvironmentOpenURL() async throws {
        let expectedURL = URL(string: "https://example.com/override")!

        let defaultCalled = XCTestExpectation(description: "default openURL should NOT be called")
        defaultCalled.isInverted = true
        environment.openURL = { _ in
            defaultCalled.fulfill()
        }

        let customCalled = expectation(description: "custom handler called")
        let sdk = KlaviyoSDK().registerDeepLinkHandler { url in
            XCTAssertEqual(url, expectedURL)
            customCalled.fulfill()
        }
        _ = sdk // silence unused warning; method is @discardableResult but we still keep consistency

        let store = TestStore(initialState: KlaviyoState(queue: [], requestsInFlight: []), reducer: KlaviyoReducer())
        _ = await store.send(.openDeepLink(expectedURL))

        await fulfillment(of: [customCalled], timeout: 1.0)
        await fulfillment(of: [defaultCalled], timeout: 0.2)
    }

    @MainActor
    func testHandleNotificationResponseUsesInjectedDeepLinkHandler() async throws {
        let urlString = "https://example.com/deeplink"
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "url": urlString
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        // If environment.openURL gets called here, we want to know (it should not be)
        let envCalled = XCTestExpectation(description: "environment.openURL should not be called")
        envCalled.isInverted = true
        environment.openURL = { _ in envCalled.fulfill() }

        let handlerCalled = expectation(description: "injected deep link handler called")
        let completionCalled = expectation(description: "completion handler called")

        let sdk = KlaviyoSDK()
        let result = sdk.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        }, deepLinkHandler: { url in
            XCTAssertEqual(url.absoluteString, urlString)
            handlerCalled.fulfill()
        })

        XCTAssertTrue(result)
        await fulfillment(of: [handlerCalled, completionCalled], timeout: 1.0)
        await fulfillment(of: [envCalled], timeout: 0.2)
    }

    @MainActor
    func testHandleNotificationResponseDispatchesOpenDeepLinkWhenNoHandler() async throws {
        let urlString = "https://example.com/deeplink2"
        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "1"],
            "url": urlString
        ]
        let response = try UNNotificationResponse.with(userInfo: userInfo)

        let openCalled = expectation(description: "environment.openURL called via reducer effect")
        environment.openURL = { url in
            XCTAssertEqual(url.absoluteString, urlString)
            openCalled.fulfill()
        }

        let completionCalled = expectation(description: "completion handler called")

        let sdk = KlaviyoSDK()
        let result = sdk.handle(notificationResponse: response, withCompletionHandler: {
            completionCalled.fulfill()
        })

        XCTAssertTrue(result)
        await fulfillment(of: [openCalled, completionCalled], timeout: 1.0)
    }
}
