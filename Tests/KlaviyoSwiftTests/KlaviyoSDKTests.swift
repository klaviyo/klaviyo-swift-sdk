//
//  File.swift
//  
//
//  Created by Noah Durell on 2/21/23.
//

import Foundation
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift


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
        environment.analytics.send = { action in
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
        let profile = Profile(attributes: .init())
        let expectation = setupActionAssertion(expectedAction: .enqueueProfile(profile))
        
        klaviyo.set(profile: profile)
        
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test create event
    func testCreateEvent() throws {
        let event = Event(attributes: .init(name: .OrderedProduct))
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(event))
        
        klaviyo.create(event: event)
        
        wait(for: [expectation], timeout: 1.0)
    }

    //MARK: test set push token
    func testSetPushToken() throws {
        let tokenData = "mytoken".data(using: .utf8)!
        let expectation = setupActionAssertion(expectedAction: .setPushToken(tokenData.reduce("", {$0 + String(format: "%02.2hhx", $1)})))
        
        _ = klaviyo.set(pushToken: tokenData)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    //MARK: test set external id
    func testSetExternalId() throws {
        let expectation = setupActionAssertion(expectedAction: .setExternalId("foo"))
        
        _ = klaviyo.set(externalId: "foo")
        
        wait(for: [expectation], timeout: 1.0)
    }

    //MARK: test handle push notification
    func testHandlePushNotification() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let push_body = ["body": [
            "_k" : [
                "foo": "bar"
            ]
        ]]
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(.init(attributes: .init(name: .OpenedPush, properties: push_body))))
        let response = try UNNotificationResponse.with(userInfo: push_body)
        let handled = klaviyo.handle(notificationResponse: response){
            callback.fulfill()
        }
        
        wait(for: [expectation, callback], timeout: 1.0)
        XCTAssertTrue(handled)
    }
    
    //MARK: test unhandle push notification
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
        let handled = klaviyo.handle(notificationResponse: response){
            callback.fulfill()
        }
        
        wait(for: [callback], timeout: 1.0)
        XCTAssertFalse(handled)
    }

}
