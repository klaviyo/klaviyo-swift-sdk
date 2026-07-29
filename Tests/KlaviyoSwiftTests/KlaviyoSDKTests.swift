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

@MainActor
class KlaviyoSDKTests: XCTestCase {
    // MARK: Properties

    var klaviyo = KlaviyoSDK()

    // MARK: Setup

    override func setUpWithError() throws {
        klaviyo = KlaviyoSDK()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        KlaviyoNotificationDelegate.shared.clearAutoTracked()
        BadgeManager.resetToProduction()
        DeepLinkManager.resetToProduction()
    }

    override func tearDown() async throws {
        environment = KlaviyoEnvironment.test()
        BadgeManager.resetToProduction()
        DeepLinkManager.resetToProduction()
        klaviyo.setLoggingEnabled(true)
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

    func testInitializeSDk() {
        let expectation = setupActionAssertion(expectedAction: .initialize(TEST_API_KEY))

        klaviyo.initialize(with: TEST_API_KEY)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set proprety

    func testSetFirstName() {
        let expectation = setupActionAssertion(expectedAction: .setProfileProperty(.firstName, "test"))

        klaviyo.set(profileAttribute: .firstName, value: "test")

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set profile

    func testSetProfile() {
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

    func testCreateEvent() {
        let event = Event(name: .openedAppMetric)
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(event))

        klaviyo.create(event: event)

        wait(for: [expectation], timeout: 1.0)
    }

    func testCreateEventFromDocumentation() {
        let event = Event(name: .addedToCartMetric, properties: [
            "Total Price": 10.99,
            "Items Purchased": ["Hot Dog", "Fries", "Shake"]
        ], value: 10.99)
        let expectation = setupActionAssertion(expectedAction: .enqueueEvent(event))

        klaviyo.create(event: event)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set push token

    func testSetPushToken() {
        let tokenData = "mytoken".data(using: .utf8)!
        let strToken = tokenData.reduce("") { $0 + String(format: "%02.2hhx", $1) }
        let expectation = setupActionAssertion(expectedAction: .setPushToken(strToken, .authorized))

        klaviyo.set(pushToken: tokenData)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: test set external id

    func testSetExternalId() {
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
        let syncExpectation = XCTestExpectation(description: "BadgeManager.syncBadgeCount called for unhandled notification")
        BadgeManager.syncBadgeCountSpy = { syncExpectation.fulfill() }
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

        wait(for: [callback, syncExpectation], timeout: 1.0)
        XCTAssertFalse(handled)
    }

    // MARK: test property getters

    func testPropertyGetters() {
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

    // MARK: - EventDispatcher Registration Tests

    func testKlaviyoSDKInitRegistersAggregateEventDispatch() {
        _ = KlaviyoSDK() // registration happens in init
        let payload = Data("agg".utf8)
        let expectation = setupActionAssertion(expectedAction: .enqueueAggregateEvent(payload))
        EventDispatcher.shared.dispatch(.aggregateEvent(payload))
        wait(for: [expectation], timeout: 1.0)
    }

    func testKlaviyoSDKInitRegistersDeepLinkDispatch() async {
        _ = KlaviyoSDK()
        let url = URL(string: "https://example.com")!
        let opened = expectation(description: "openDeepLink invoked with URL")
        DeepLinkManager.openDeepLinkSpy = { dispatchedURL in
            XCTAssertEqual(dispatchedURL, url)
            opened.fulfill()
        }
        EventDispatcher.shared.dispatch(.deepLink(url))
        await fulfillment(of: [opened], timeout: 1.0)
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

        klaviyo.unregisterDeepLinkHandler()

        XCTAssertFalse(klaviyo.isDeepLinkHandlerRegistered, "Handler should be unregistered")
    }

    func testIsDeepLinkHandlerRegisteredInitialState() {
        let freshSDK = KlaviyoSDK()
        XCTAssertFalse(freshSDK.isDeepLinkHandlerRegistered, "New SDK instance should have no handler registered")
    }

    // MARK: - Logging Toggle Tests

    func testLoggingEnabledByDefault() {
        XCTAssertTrue(klaviyo.isLoggingEnabled, "Logging should be enabled by default")
    }

    func testSetLoggingDisabled() {
        klaviyo.setLoggingEnabled(false)
        XCTAssertFalse(klaviyo.isLoggingEnabled, "Logging should be disabled after setLoggingEnabled(false)")
    }

    func testSetLoggingReEnabled() {
        klaviyo.setLoggingEnabled(false)
        XCTAssertFalse(klaviyo.isLoggingEnabled)

        klaviyo.setLoggingEnabled(true)
        XCTAssertTrue(klaviyo.isLoggingEnabled, "Logging should be re-enabled after setLoggingEnabled(true)")
    }

    func testSetLoggingEnabledIsChainable() {
        let result = klaviyo.setLoggingEnabled(false)
        XCTAssertNotNil(result, "setLoggingEnabled should return a KlaviyoSDK instance for chaining")
    }

    // MARK: - Push Action Button Tests

    func testHandleActionButtonTap_DeepLinkWithAllProperties() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let eventCaptured = XCTestExpectation(description: "opened_push event enqueued")
        let actionURL = try XCTUnwrap(URL(string: "myapp://products/123"))
        let actionId = "com.klaviyo.test.shop"
        let buttonLabel = "Shop Now"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_notification_001",
                "message_id": "msg_123",
                "campaign_id": "camp_456",
                "action_buttons": [
                    [
                        "id": actionId,
                        "label": buttonLabel,
                        "action": "deep_link",
                        "url": actionURL.absoluteString
                    ]
                ]
            ]
        ]

        var capturedActions: [KlaviyoAction] = []
        klaviyoSwiftEnvironment.send = { action in
            capturedActions.append(action)
            // `handle(notificationResponse:)` enqueues the event and invokes the
            // completion handler on two *independent* unstructured Tasks, so the
            // callback can fulfill before the event is captured. Fulfill on the
            // captured event too and wait on both, rather than asserting on a
            // side effect that may not have landed yet.
            if case let .enqueueEvent(event) = action, event.metric.name == ._openedPush {
                eventCaptured.fulfill()
            }
            return nil
        }

        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: actionId
        )

        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, eventCaptured], timeout: 1.0)
        XCTAssertTrue(handled, "Should handle Klaviyo notification with action button")

        // Verify event was created
        let eventAction = capturedActions.first { action in
            if case let .enqueueEvent(event) = action {
                return event.metric.name == ._openedPush
            }
            return false
        }
        XCTAssertNotNil(eventAction, "Should create $opened_push event")

        // Verify event properties
        if case let .enqueueEvent(event) = try XCTUnwrap(eventAction) {
            XCTAssertEqual(event.metric.name.value, "$opened_push", "Event name should be $opened_push")
            XCTAssertEqual(event.properties["Button Label"] as? String, buttonLabel, "Should include Button Label")
            XCTAssertEqual(event.properties["Button ID"] as? String, actionId, "Should include Button ID")
            XCTAssertEqual(event.properties["Button Action"] as? String, "Deep Link", "Should include Button Action with correct value")
            XCTAssertEqual(event.properties["Button Link"] as? String, actionURL.absoluteString, "Should include Button Link")

            // Verify standard push notification properties are preserved
            let body = event.properties["body"] as? [String: Any]
            XCTAssertNotNil(body, "Should preserve body dictionary")
            XCTAssertEqual(body?["_k"] as? String, "test_notification_001", "Should preserve _k property")
        }
    }

    func testHandleActionButtonTap_OpenAppWithoutURL() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let eventCaptured = XCTestExpectation(description: "opened_push event enqueued")
        let actionId = "com.klaviyo.test.open"
        let buttonLabel = "Open App"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_notification_002",
                "action_buttons": [
                    [
                        "id": actionId,
                        "label": buttonLabel,
                        "action": "open_app"
                        // No URL for openApp
                    ]
                ]
            ]
        ]

        var capturedActions: [KlaviyoAction] = []
        klaviyoSwiftEnvironment.send = { action in
            capturedActions.append(action)
            // `handle(notificationResponse:)` enqueues the event and invokes the
            // completion handler on two *independent* unstructured Tasks, so the
            // callback can fulfill before the event is captured. Fulfill on the
            // captured event too and wait on both, rather than asserting on a
            // side effect that may not have landed yet.
            if case let .enqueueEvent(event) = action, event.metric.name == ._openedPush {
                eventCaptured.fulfill()
            }
            return nil
        }

        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: actionId
        )

        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, eventCaptured], timeout: 1.0)
        XCTAssertTrue(handled)

        // Verify event was created
        let eventAction = capturedActions.first { action in
            if case let .enqueueEvent(event) = action {
                return event.metric.name == ._openedPush
            }
            return false
        }
        XCTAssertNotNil(eventAction, "Should create $opened_push event")

        // Verify event properties
        if case let .enqueueEvent(event) = try XCTUnwrap(eventAction) {
            XCTAssertEqual(event.metric.name.value, "$opened_push", "Event name should be $opened_push")
            XCTAssertEqual(event.properties["Button Label"] as? String, buttonLabel, "Should include Button Label")
            XCTAssertEqual(event.properties["Button ID"] as? String, actionId, "Should include Button ID")
            XCTAssertEqual(event.properties["Button Action"] as? String, "Open App", "Should include Button Action with correct value")
            XCTAssertNil(event.properties["Button Link"], "Should NOT include Button Link for openApp action")
        }
    }

    func testHandleActionButtonTap_NotTriggeredOnBodyTap() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let eventCaptured = XCTestExpectation(description: "opened_push event enqueued")
        let actionId = "com.klaviyo.test.button"
        let buttonLabel = "Tap Me"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_notification_004",
                "action_buttons": [
                    [
                        "id": actionId,
                        "label": buttonLabel,
                        "action": "open_app"
                    ]
                ]
            ]
        ]

        var capturedActions: [KlaviyoAction] = []
        klaviyoSwiftEnvironment.send = { action in
            capturedActions.append(action)
            // `handle(notificationResponse:)` enqueues the event and invokes the
            // completion handler on two *independent* unstructured Tasks, so the
            // callback can fulfill before the event is captured. Fulfill on the
            // captured event too and wait on both, rather than asserting on a
            // side effect that may not have landed yet.
            if case let .enqueueEvent(event) = action, event.metric.name == ._openedPush {
                eventCaptured.fulfill()
            }
            return nil
        }

        // Tap notification body (default action identifier)
        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, eventCaptured], timeout: 1.0)
        XCTAssertTrue(handled)

        // Verify event was created (for body tap)
        let eventAction = capturedActions.first { action in
            if case let .enqueueEvent(event) = action {
                return event.metric.name == ._openedPush
            }
            return false
        }
        XCTAssertNotNil(eventAction, "Should create $opened_push event for body tap")

        // Verify button properties are NOT included for body tap
        if case let .enqueueEvent(event) = try XCTUnwrap(eventAction) {
            XCTAssertEqual(event.metric.name.value, "$opened_push", "Event name should be $opened_push")
            XCTAssertNil(event.properties["Button ID"], "Should NOT include Button ID for body tap")
            XCTAssertNil(event.properties["Button Label"], "Should NOT include Button Label for body tap")
            XCTAssertNil(event.properties["Button Action"], "Should NOT include Button Action for body tap")
            XCTAssertNil(event.properties["Button Link"], "Should NOT include Button Link for body tap")
        }
    }

    // MARK: - Double-track guard

    func testHandleShortCircuitsWhenAutoTracked() throws {
        // Given
        let callback = XCTestExpectation(description: "completion is called")
        let noEvent = XCTestExpectation(description: "no enqueueEvent dispatched")
        noEvent.isInverted = true
        klaviyoSwiftEnvironment.send = { action in
            if case .enqueueEvent = action { noEvent.fulfill() }
            return nil
        }
        let pushBody: [AnyHashable: Any] = ["body": ["_k": ["foo": "bar"]]]
        let response = try UNNotificationResponse.with(userInfo: pushBody)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)

        // When
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        // Then
        wait(for: [callback, noEvent], timeout: 1.0)
        XCTAssertTrue(handled)
    }

    func testProxyThenManualHandleEmitsOneEvent() throws {
        // Given — proxy calls handle then marks the request ID (mirrors didReceive implementation)
        let proxyCallback = XCTestExpectation(description: "proxy completion fires")
        let manualCallback = XCTestExpectation(description: "manual completion fires")
        var enqueueCount = 0
        klaviyoSwiftEnvironment.send = { action in
            if case .enqueueEvent = action { enqueueCount += 1 }
            return nil
        }
        let pushBody: [AnyHashable: Any] = ["body": ["_k": ["foo": "bar"]]]
        let response = try UNNotificationResponse.with(userInfo: pushBody)

        // When (proxy path)
        let wasTracked = klaviyo.handle(notificationResponse: response) { proxyCallback.fulfill() }
        XCTAssertTrue(wasTracked)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(
            dedupKey: response.klaviyoDedupKey
        )
        wait(for: [proxyCallback], timeout: 1.0)

        // Then — exactly one event emitted on the proxy pass
        XCTAssertEqual(enqueueCount, 1, "proxy call should emit exactly one _openedPush")

        // When (manual host path for same response)
        let handled2 = klaviyo.handle(notificationResponse: response) { manualCallback.fulfill() }
        XCTAssertTrue(handled2)
        wait(for: [manualCallback], timeout: 1.0)

        // Then — no second event emitted
        XCTAssertEqual(enqueueCount, 1, "manual handle must not emit a second event")
    }

    func testHandleShortCircuitSuppressesDeepLinkDispatch() throws {
        // Given
        let callback = XCTestExpectation(description: "completion is called")
        let noDeepLink = XCTestExpectation(description: "no openDeepLink dispatched")
        noDeepLink.isInverted = true
        DeepLinkManager.openDeepLinkSpy = { _ in noDeepLink.fulfill() }
        let pushBody: [AnyHashable: Any] = [
            "body": ["_k": ["foo": "bar"]],
            "url": "https://example.com/deeplink"
        ]
        let response = try UNNotificationResponse.with(userInfo: pushBody)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)

        // When
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        // Then
        wait(for: [callback, noDeepLink], timeout: 1.0)
        XCTAssertTrue(handled)
    }

    func testProxyThenManualHandleDedupsViaTm() throws {
        // Given — a real Klaviyo payload with tm present
        let proxyCallback = XCTestExpectation(description: "proxy completion fires")
        let manualCallback = XCTestExpectation(description: "manual completion fires")
        var enqueueCount = 0
        klaviyoSwiftEnvironment.send = { action in
            if case .enqueueEvent = action { enqueueCount += 1 }
            return nil
        }
        let pushBody: [AnyHashable: Any] = [
            "body": [
                "_k": [
                    "tm": "01KV8CN3SH8N7MM5ZYNX40QCFH",
                    "m": "01KT4QQ8QPYH4EN7BH3BH259TD",
                    "$message": "01KT4QQ8QPYH4EN7BH3BH259TD"
                ]
            ]
        ]
        let response = try UNNotificationResponse.with(userInfo: pushBody)

        // When (proxy path) - mark using the tm-based dedup key
        let wasTracked = klaviyo.handle(notificationResponse: response) { proxyCallback.fulfill() }
        XCTAssertTrue(wasTracked)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)
        wait(for: [proxyCallback], timeout: 1.0)
        XCTAssertEqual(enqueueCount, 1, "proxy call should emit exactly one _openedPush")

        // When (manual host path) — same tm key must short-circuit
        let handled2 = klaviyo.handle(notificationResponse: response) { manualCallback.fulfill() }
        XCTAssertTrue(handled2)
        wait(for: [manualCallback], timeout: 1.0)
        XCTAssertEqual(enqueueCount, 1, "manual handle must not emit a second event")
    }

    func testHandleShortCircuitsForActionButtonTapWhenAutoTracked() throws {
        // Given
        let callback = XCTestExpectation(description: "completion is called")
        let noEvent = XCTestExpectation(description: "no enqueueEvent dispatched")
        noEvent.isInverted = true
        klaviyoSwiftEnvironment.send = { action in
            if case .enqueueEvent = action { noEvent.fulfill() }
            return nil
        }
        let actionId = "com.klaviyo.test.button.dedup"
        let pushBody: [AnyHashable: Any] = [
            "body": [
                "_k": "test_dedup_action",
                "action_buttons": [["id": actionId, "label": "Tap Me", "action": "open_app"]]
            ]
        ]
        let response = try UNNotificationResponse.with(userInfo: pushBody, actionIdentifier: actionId)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)

        // When
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        // Then
        wait(for: [callback, noEvent], timeout: 1.0)
        XCTAssertTrue(handled)
    }

    // MARK: - web_url tests

    // Deep link / web URL resolution now routes through `DeepLinkManager`
    // (`openDeepLinkSpy`/`openExternalURLSpy`), not a dispatched `KlaviyoAction` — only
    // the `$opened_push` event track still goes through `klaviyoSwiftEnvironment.send`.

    func testHandleBodyTap_WebUrlDispatchesOpenWebUrl() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let eventDispatched = XCTestExpectation(description: "event action dispatched")
        let webURL = try XCTUnwrap(URL(string: "https://example.com/sale"))

        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "test_web_url"],
            "web_url": webURL.absoluteString
        ]

        klaviyoSwiftEnvironment.send = { action in
            if case .enqueueEvent = action { eventDispatched.fulfill() }
            return nil
        }
        let externalUrlInvoked = XCTestExpectation(description: "openExternalURL invoked")
        DeepLinkManager.openExternalURLSpy = { dispatchedUrl in
            XCTAssertEqual(dispatchedUrl, webURL)
            externalUrlInvoked.fulfill()
        }

        let response = try UNNotificationResponse.with(userInfo: userInfo)
        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, eventDispatched, externalUrlInvoked], timeout: 1.0)
        XCTAssertTrue(handled)
    }

    func testHandleBodyTap_DeepLinkUnchangedWhenWebUrlAbsent() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let eventDispatched = XCTestExpectation(description: "event action dispatched")
        let deepURL = try XCTUnwrap(URL(string: "myapp://path"))

        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "test_deep_link_regression"],
            "url": deepURL.absoluteString
        ]

        klaviyoSwiftEnvironment.send = { action in
            if case .enqueueEvent = action { eventDispatched.fulfill() }
            return nil
        }
        let deepLinkInvoked = XCTestExpectation(description: "openDeepLink invoked")
        DeepLinkManager.openDeepLinkSpy = { dispatchedUrl in
            XCTAssertEqual(dispatchedUrl, deepURL)
            deepLinkInvoked.fulfill()
        }

        let response = try UNNotificationResponse.with(userInfo: userInfo)
        _ = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, eventDispatched, deepLinkInvoked], timeout: 1.0)
    }

    func testHandleBodyTap_DeepLinkTakesPrecedenceOverWebUrl() throws {
        // Defensive: if backend ever ships both web_url and url, the deep link wins so
        // the user stays in the host app. The composer UI enforces a single action type
        // at creation, so this only fires via direct-API or test-tooling sends.
        let callback = XCTestExpectation(description: "callback is made")
        let webURL = try XCTUnwrap(URL(string: "https://example.com/sale"))
        let deepURL = try XCTUnwrap(URL(string: "myapp://path"))

        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "test_both_present"],
            "web_url": webURL.absoluteString,
            "url": deepURL.absoluteString
        ]

        let deepLinkInvoked = XCTestExpectation(description: "openDeepLink invoked")
        DeepLinkManager.openDeepLinkSpy = { dispatchedUrl in
            XCTAssertEqual(dispatchedUrl, deepURL)
            deepLinkInvoked.fulfill()
        }
        let externalUrlNotInvoked = XCTestExpectation(description: "openExternalURL must not be invoked")
        externalUrlNotInvoked.isInverted = true
        DeepLinkManager.openExternalURLSpy = { _ in externalUrlNotInvoked.fulfill() }

        let response = try UNNotificationResponse.with(userInfo: userInfo)
        _ = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, deepLinkInvoked], timeout: 1.0)
        wait(for: [externalUrlNotInvoked], timeout: 0.3)
    }

    func testHandleActionButtonTap_OpenUrlButton() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let actionURL = try XCTUnwrap(URL(string: "https://example.com/promo"))
        let actionId = "com.klaviyo.test.web"
        let buttonLabel = "Visit Site"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_open_url_button",
                "action_buttons": [
                    [
                        "id": actionId,
                        "label": buttonLabel,
                        "action": "open_url",
                        "url": actionURL.absoluteString
                    ]
                ]
            ]
        ]

        var capturedActions: [KlaviyoAction] = []
        let eventDispatched = XCTestExpectation(description: "event action dispatched")
        klaviyoSwiftEnvironment.send = { action in
            capturedActions.append(action)
            if case .enqueueEvent = action { eventDispatched.fulfill() }
            return nil
        }
        let externalUrlInvoked = XCTestExpectation(description: "openExternalURL invoked")
        DeepLinkManager.openExternalURLSpy = { dispatchedUrl in
            XCTAssertEqual(dispatchedUrl, actionURL)
            externalUrlInvoked.fulfill()
        }

        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: actionId
        )

        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, eventDispatched, externalUrlInvoked], timeout: 1.0)
        XCTAssertTrue(handled)

        let eventAction = capturedActions.first { action in
            if case let .enqueueEvent(event) = action {
                return event.metric.name == ._openedPush
            }
            return false
        }
        XCTAssertNotNil(eventAction)
        if case let .enqueueEvent(event) = try XCTUnwrap(eventAction) {
            XCTAssertEqual(event.properties["Button Action"] as? String, "Open URL")
            XCTAssertEqual(event.properties["Button Link"] as? String, actionURL.absoluteString)
        }
    }

    func testHandleActionButtonTap_OpenUrlButtonWithBlockedSchemeDoesNotDispatch() throws {
        let callback = XCTestExpectation(description: "callback is made")
        let actionURL = try XCTUnwrap(URL(string: "javascript:alert(1)"))
        let actionId = "com.klaviyo.test.blocked"
        let buttonLabel = "Bad Button"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_open_url_blocked",
                "action_buttons": [
                    [
                        "id": actionId,
                        "label": buttonLabel,
                        "action": "open_url",
                        "url": actionURL.absoluteString
                    ]
                ]
            ]
        ]

        var capturedActions: [KlaviyoAction] = []
        let eventDispatched = XCTestExpectation(description: "event action dispatched")
        klaviyoSwiftEnvironment.send = { action in
            capturedActions.append(action)
            if case .enqueueEvent = action { eventDispatched.fulfill() }
            return nil
        }
        let externalUrlNotInvoked = XCTestExpectation(description: "openExternalURL must not be invoked for blocked scheme")
        externalUrlNotInvoked.isInverted = true
        DeepLinkManager.openExternalURLSpy = { _ in externalUrlNotInvoked.fulfill() }

        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: actionId
        )

        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        wait(for: [callback, eventDispatched], timeout: 1.0)
        wait(for: [externalUrlNotInvoked], timeout: 0.3)
        XCTAssertTrue(handled)

        let eventAction = capturedActions.first { action in
            if case let .enqueueEvent(event) = action {
                return event.metric.name == ._openedPush
            }
            return false
        }
        XCTAssertNotNil(eventAction, "Tap should still be tracked even when the scheme is blocked")
    }
}
