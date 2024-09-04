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
            lastName: "Smith")
        let expectation = setupActionAssertion(expectedAction: .enqueueProfile(profile))

        klaviyo.set(profile: profile)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test create event

    func testCreateEvent() throws {
        let event = Event(name: .OpenedAppMetric)
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(event))

        klaviyo.create(event: event)

        wait(for: [expectation], timeout: 1.0)
    }

    func testCreateEventFromDocumentation() throws {
        let event = Event(name: .AddedToCartMetric, properties: [
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
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(.init(name: .OpenedPush, properties: push_body)))
        let response = try UNNotificationResponse.with(userInfo: push_body)
        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [expectation, callback], timeout: 1.0)
        XCTAssertTrue(handled)
    }

    // MARK: test unhandle push notification

    func testUnhandlePushNotification() throws {
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

        wait(for: [callback], timeout: 1.0)
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
}
