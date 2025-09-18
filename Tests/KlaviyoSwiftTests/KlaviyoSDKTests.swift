//
//  KlaviyoSDKTests.swift
//
//
//  Created by Noah Durell on 2/21/23.
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

// MARK: - KlaviyoSDKTests

class KlaviyoSDKTests: XCTestCase {
    // MARK: Properties

    var klaviyo = KlaviyoSDK()

    // MARK: Setup

    override func setUpWithError() throws {
        klaviyo = KlaviyoSDK()
        environment = KlaviyoEnvironment.test()
    }

    override func tearDown() async throws {
        environment = KlaviyoEnvironment.test()
    }

    func setupActionAssertion(expectedAction: KlaviyoAction, file: StaticString = #filePath, line: UInt = #line) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "wait for action \(expectedAction)")
        klaviyoSwiftEnvironment.send = { action in
            XCTAssertEqual(action, expectedAction, file: file, line: line)
            expectation.fulfill()
            return nil
        }
        return expectation
    }

    // MARK: Tests

    func testKlaviyoSDKInit() {
        XCTAssertNotNil(klaviyo)
    }

    // MARK: test initialize

    func testInitializeSDk() throws {
        let expectation = setupActionAssertion(expectedAction: .initialize(TEST_API_KEY))

        klaviyo.initialize(with: TEST_API_KEY)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set proprety

    func testSetFirstName() throws {
        let expectation = setupActionAssertion(expectedAction: .setProfileProperty(.firstName, "test"))

        klaviyo.set(profileAttribute: .firstName, value: "test")

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set profile

    func testSetProfile() throws {
        let profile = Profile(
            email: "john.smith@example.com",
            phoneNumber: "+15555551212",
            firstName: "John",
            lastName: "Smith"
        )
        let expectation = setupActionAssertion(expectedAction: .enqueueProfile(profile))

        klaviyo.set(profile: profile)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test create event

    func testCreateEvent() throws {
        let event = Event(name: .openedAppMetric)
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(event))

        klaviyo.create(event: event)

        wait(for: [expectation], timeout: 1.0)
    }

    func testCreateEventFromDocumentation() throws {
        let event = Event(name: .addedToCartMetric, properties: [
            "Total Price": 10.99,
            "Items Purchased": ["Hot Dog", "Fries", "Shake"]
        ], value: 10.99)
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(event))

        klaviyo.create(event: event)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set push token

    func testSetPushToken() throws {
        let tokenData = "mytoken".data(using: .utf8)!
        let strToken = tokenData.reduce("") { $0 + String(format: "%02.2hhx", $1) }
        let expectation = setupActionAssertion(expectedAction: .setPushToken(strToken, .authorized))

        klaviyo.set(pushToken: tokenData)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set external id

    func testSetExternalId() throws {
        let expectation = setupActionAssertion(expectedAction: .setExternalId("foo"))

        _ = klaviyo.set(externalId: "foo")

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test handle push notification

    func testHandlePushNotification() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let push_body = ["body": [
            "_k": [
                "foo": "bar"
            ]
        ]]
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(.init(name: ._openedPush, properties: push_body)))
        let response = try UNNotificationResponse.with(userInfo: push_body)
        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [expectation, callback], timeout: 1.0)
        XCTAssertTrue(handled)
    }

    // MARK: test unhandle push notification

    func testUnhandlePushNotification() throws {
        let expectation = setupActionAssertion(expectedAction: .syncBadgeCount)
        let callback = XCTestExpectation(description: "callback is not made")
        callback.isInverted = true
        let data: [AnyHashable: Any] = [
            "data": [
                "type": "OPEN_ARTICLE",
                "articleId": "1",
                "articleType": "Fiction",
                "articleTag": "1"
            ]
        ]
        let response = try UNNotificationResponse.with(userInfo: data)
        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, expectation], timeout: 1.0)
        XCTAssertFalse(handled)
    }

    // MARK: test property getters

    func testPropertyGetters() throws {
        klaviyoSwiftEnvironment.state = { KlaviyoState(email: "foo@foo.com", phoneNumber: "555BLOB", externalId: "my_test_id", pushTokenData: .init(pushToken: "blobtoken", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.appContextInfo())), queue: []) }
        let klaviyo = KlaviyoSDK()
        XCTAssertEqual("foo@foo.com", klaviyo.email)
        XCTAssertEqual("555BLOB", klaviyo.phoneNumber)
        XCTAssertEqual("blobtoken", klaviyo.pushToken)
        XCTAssertEqual("my_test_id", klaviyo.externalId)
    }

    // MARK: tracking link handling

    func testHandleUniversalTrackingLinkDispatchesTrackingLinkReceived() throws {
        let url = try XCTUnwrap(URL(string: "https://email.klaviyo.com/u/tracking/link"))
        let expectation = setupActionAssertion(expectedAction: .trackingLinkReceived(url))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertTrue(result, "Should return true for valid HTTPS universal tracking link")
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleUniversalTrackingLinkWithHTTPURL() throws {
        let url = try XCTUnwrap(URL(string: "http://email.klaviyo.com/u/tracking/link"))
        let expectation = setupActionAssertion(expectedAction: .trackingLinkReceived(url))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertTrue(result, "Should return true for valid HTTP universal tracking link")
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleUniversalTrackingLinkWithDifferentPath() throws {
        let url = try XCTUnwrap(URL(string: "https://manage.kmail-lists.com/u/campaign/12345"))
        let expectation = setupActionAssertion(expectedAction: .trackingLinkReceived(url))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertTrue(result, "Should return true for universal tracking link with different domain")
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleUniversalTrackingLinkRejectsNonTrackingURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/regular/path"))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertFalse(result, "Should return false for non-universal tracking URL")
    }

    func testHandleUniversalTrackingLinkRejectsCustomScheme() throws {
        let url = try XCTUnwrap(URL(string: "myapp://u/tracking/link"))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertFalse(result, "Should return false for custom scheme URL")
    }

    func testHandleUniversalTrackingLinkRejectsWrongPath() throws {
        let url = try XCTUnwrap(URL(string: "https://email.klaviyo.com/v/tracking/link"))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertFalse(result, "Should return false for URL without /u/ path prefix")
    }

    func testHandleUniversalTrackingLinkRejectsPathNotStartingWithU() throws {
        let url = try XCTUnwrap(URL(string: "https://email.klaviyo.com/user/tracking/link"))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertFalse(result, "Should return false for URL with path starting with /user/ instead of /u/")
    }

    func testHandleUniversalTrackingLinkWithQueryParameters() throws {
        let url = try XCTUnwrap(URL(string: "https://email.klaviyo.com/u/tracking/link?utm_source=email&utm_campaign=test"))
        let expectation = setupActionAssertion(expectedAction: .trackingLinkReceived(url))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertTrue(result, "Should return true for universal tracking link with query parameters")
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleUniversalTrackingLinkWithFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://email.klaviyo.com/u/tracking/link#section"))
        let expectation = setupActionAssertion(expectedAction: .trackingLinkReceived(url))

        let result = klaviyo.handleUniversalTrackingLink(url)

        XCTAssertTrue(result, "Should return true for universal tracking link with fragment")
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleUniversalTrackingLinkEdgeCases() throws {
        // Test /u without trailing slash should fail (doesn't match hasPrefix("/u/"))
        let justUURL = try XCTUnwrap(URL(string: "https://example.com/u"))
        let justUResult = klaviyo.handleUniversalTrackingLink(justUURL)
        XCTAssertFalse(justUResult, "Should return false for path /u without trailing slash")

        // Test root path should fail
        let rootURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let rootResult = klaviyo.handleUniversalTrackingLink(rootURL)
        XCTAssertFalse(rootResult, "Should return false for root path")

        // Test path with /u/ in the middle should fail
        let middleUURL = try XCTUnwrap(URL(string: "https://example.com/api/u/track"))
        let middleUResult = klaviyo.handleUniversalTrackingLink(middleUURL)
        XCTAssertFalse(middleUResult, "Should return false for path with /u/ in the middle")
    }

    // MARK: - Deep Link Handler Registration Tests

    func testRegisterDeepLinkHandler() {
        XCTAssertFalse(klaviyo.isDeepLinkHandlerRegistered, "Should start with no handler registered")

        let handler = klaviyo.registerDeepLinkHandler { _ in }

        XCTAssertTrue(klaviyo.isDeepLinkHandlerRegistered, "Handler should be registered after registerDeepLinkHandler")
        XCTAssertNotNil(handler, "Should return a non-nil handler reference")
    }

    func testUnregisterDeepLinkHandler() {
        klaviyo.registerDeepLinkHandler { _ in }
        XCTAssertTrue(klaviyo.isDeepLinkHandlerRegistered, "Handler should be registered")

        _ = klaviyo.unregisterDeepLinkHandler()

        XCTAssertFalse(klaviyo.isDeepLinkHandlerRegistered, "Handler should be unregistered")
    }

    func testIsDeepLinkHandlerRegisteredInitialState() {
        let freshSDK = KlaviyoSDK()
        XCTAssertFalse(freshSDK.isDeepLinkHandlerRegistered, "New SDK instance should have no handler registered")
    }
}
