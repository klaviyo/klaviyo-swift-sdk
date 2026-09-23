//
//  KlaviyoSDKTests.swift
//
//
//  Created by Noah Durell on 2/21/23.
//
//  Facade coverage for the public `KlaviyoSDK` surface. The public methods forward to
//  `KlaviyoCommands` (via `dispatchOnMainThread`) instead of dispatching TCA actions, so these
//  tests assert the resulting Core-store / QueueStore side effects rather than a captured action.
//

@testable import KlaviyoCore
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import Foundation
import XCTest

// MARK: - KlaviyoSDKTests

@MainActor
class KlaviyoSDKTests: XCTestCase {
    // MARK: Properties

    var klaviyo = KlaviyoSDK()
    /// Live recording of every request persisted to the shared `QueueStore` this test.
    private var recordedRequests: () -> [KlaviyoRequest] = { [] }

    // MARK: Setup

    override func setUpWithError() throws {
        klaviyo = KlaviyoSDK()
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        LifecycleState.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        KlaviyoNotificationDelegate.shared.clearAutoTracked()
        BadgeManager.resetToProduction()
        DeepLinkManager.resetToProduction()
    }

    override func tearDown() async throws {
        environment = KlaviyoEnvironment.test()
        LifecycleState.shared.reset()
        BadgeManager.resetToProduction()
        DeepLinkManager.resetToProduction()
        klaviyo.setLoggingEnabled(true)
    }

    // MARK: Helpers

    /// Seeds an initialized SDK (apiKey + anon identity + `.initialized` lifecycle) and installs a
    /// recording `QueueStore` so enqueued requests are observable. Facade calls that enqueue
    /// (events, profiles) land in `recordedRequests()`.
    private func seedInitializedRecording() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: environment.uuid().uuidString))
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()
        SessionState.markInitialized()
        recordedRequests = registerRecordingQueueStore()
    }

    /// Returns the `Attributes` of every recorded `_openedPush` createEvent request, paired with the
    /// owning request's priority.
    private func openedPushEvents() -> [(attributes: CreateEventPayload.Event.Attributes, priority: RequestPriority)] {
        recordedRequests().compactMap { request in
            guard case let .createEvent(_, payload) = request.endpoint,
                  payload.data.attributes.metric.data.attributes.name == "$opened_push" else {
                return nil
            }
            return (payload.data.attributes, request.priority)
        }
    }

    /// Polls until at least one `_openedPush` event is recorded. Fails (XCTFail) on timeout so a
    /// missing event surfaces loudly rather than silently passing.
    private func waitForOpenedPush(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await waitForConditionOrFail(
            timeout: timeout,
            "openedPush event not received within \(timeout)s",
            file: file,
            line: line
        ) { !self.openedPushEvents().isEmpty }
    }

    private func stringProperty(_ attributes: CreateEventPayload.Event.Attributes, _ key: String) -> String? {
        (attributes.properties.value as? [String: Any])?[key] as? String
    }

    // MARK: test initialize

    func testInitializeSDk() async throws {
        klaviyo.initialize(with: TEST_API_KEY)

        try await waitForCondition { SDKConfigStore.shared.current.apiKey == TEST_API_KEY }
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, TEST_API_KEY)
        XCTAssertNotEqual(LifecycleState.shared.current, .uninitialized)
    }

    // MARK: test set property

    func testSetFirstName() async throws {
        seedInitializedRecording()
        klaviyo.set(profileAttribute: .firstName, value: "test")

        // `set(profileAttribute:)` stages into `ProfilePropertyBuffer` via a main-queue hop. Yield
        // to let that hop settle before flushing.
        await Task.yield()
        await Task.yield()
        await ProfilePropertyBuffer.shared.flushIntoQueue()
        let firstNames: [String?] = recordedRequests().map { request in
            switch request.endpoint {
            case let .registerPushToken(_, payload):
                return payload.data.attributes.profile.data.attributes.firstName
            case let .createProfile(_, payload):
                return payload.data.attributes.firstName
            default:
                return nil
            }
        }
        XCTAssertTrue(firstNames.contains("test"), "staged firstName must fold into an enqueued request")
    }

    // MARK: test set profile

    func testSetProfile() async throws {
        seedInitializedRecording()
        let profile = Profile(
            email: "john.smith@example.com",
            phoneNumber: "+15555551212",
            firstName: "John",
            lastName: "Smith"
        )
        klaviyo.set(profile: profile)

        try await waitForCondition {
            self.recordedRequests().contains { request in
                if case .createProfile = request.endpoint { return true }
                return false
            }
        }
        let profileRequest = recordedRequests().first { request in
            if case .createProfile = request.endpoint { return true }
            return false
        }
        guard case let .createProfile(_, payload)? = profileRequest?.endpoint else {
            return XCTFail("expected a createProfile request")
        }
        XCTAssertEqual(payload.data.attributes.email, "john.smith@example.com")
        XCTAssertEqual(payload.data.attributes.phoneNumber, "+15555551212")
    }

    // MARK: test create event

    func testCreateEvent() async throws {
        seedInitializedRecording()
        klaviyo.create(event: Event(name: .openedAppMetric))

        try await waitForCondition {
            self.recordedRequests().contains { request in
                if case .createEvent = request.endpoint { return true }
                return false
            }
        }
        let eventNames: [String] = recordedRequests().compactMap { request in
            guard case let .createEvent(_, payload) = request.endpoint else { return nil }
            return payload.data.attributes.metric.data.attributes.name
        }
        XCTAssertTrue(eventNames.contains("Opened App"))
    }

    func testCreateEventFromDocumentation() async throws {
        seedInitializedRecording()
        let event = Event(name: .addedToCartMetric, properties: [
            "Total Price": 10.99,
            "Items Purchased": ["Hot Dog", "Fries", "Shake"]
        ], value: 10.99)
        klaviyo.create(event: event)

        try await waitForCondition {
            self.recordedRequests().contains { request in
                if case .createEvent = request.endpoint { return true }
                return false
            }
        }
        let eventNames: [String] = recordedRequests().compactMap { request in
            guard case let .createEvent(_, payload) = request.endpoint else { return nil }
            return payload.data.attributes.metric.data.attributes.name
        }
        XCTAssertTrue(eventNames.contains("Added to Cart"))
    }

    // MARK: test set push token

    func testSetPushToken() async throws {
        seedInitializedRecording()
        let tokenData = "mytoken".data(using: .utf8)!
        let strToken = tokenData.reduce("") { $0 + String(format: "%02.2hhx", $1) }
        klaviyo.set(pushToken: tokenData)

        try await waitForCondition { IdentityStore.shared.pushToken?.pushToken == strToken }
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, strToken)
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushEnablement, .authorized)
    }

    func testSetAutomaticPushTokenUsesAutomaticAction() async throws {
        seedInitializedRecording()
        let tokenData = "automatic-token".data(using: .utf8)!
        let stringToken = tokenData.reduce("") { $0 + String(format: "%02.2hhx", $1) }
        klaviyo.setAutomatic(pushToken: tokenData)

        try await waitForCondition { IdentityStore.shared.pushToken?.pushToken == stringToken }
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, stringToken)
    }

    func testSetAutomaticPushTokenDiscardsOlderSettingsResultThatFinishesLast() async {
        seedInitializedRecording()
        let firstToken = Data([0x01])
        let secondToken = Data([0x02])
        // `getNotificationSettings` runs from setAutomatic(pushToken:)'s unstructured Task, off
        // the main actor this test method runs on — guard the shared array against that race.
        let continuationsLock = NSLock()
        nonisolated(unsafe) var settingsContinuations: [CheckedContinuation<PushEnablement, Never>] = []
        let firstSettingsRequested = expectation(description: "first notification settings requested")
        let secondSettingsRequested = expectation(description: "second notification settings requested")
        environment.getNotificationSettings = {
            await withCheckedContinuation { continuation in
                continuationsLock.lock()
                settingsContinuations.append(continuation)
                let count = settingsContinuations.count
                continuationsLock.unlock()
                if count == 1 {
                    firstSettingsRequested.fulfill()
                } else {
                    secondSettingsRequested.fulfill()
                }
            }
        }

        KlaviyoSDK().setAutomatic(pushToken: firstToken)
        await fulfillment(of: [firstSettingsRequested], timeout: 1.0)
        KlaviyoSDK().setAutomatic(pushToken: secondToken)
        await fulfillment(of: [secondSettingsRequested], timeout: 1.0)

        continuationsLock.lock()
        let continuations = settingsContinuations
        continuationsLock.unlock()
        XCTAssertEqual(continuations.count, 2)

        // Resolve the SECOND (latest) settings result first: its token must be applied.
        continuations[1].resume(returning: .authorized)
        let latestApplied = expectation(description: "latest automatic token applied")
        pollOnMain(latestApplied) { IdentityStore.shared.pushToken?.pushToken == "02" }
        await fulfillment(of: [latestApplied], timeout: 1.0)

        // Resolve the STALE first result last: it must be dropped (token stays "02").
        continuations[0].resume(returning: .denied)
        // Yield to give the cooperative scheduler a chance to run the stale token path if broken.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(
            IdentityStore.shared.pushToken?.pushToken, "02",
            "stale automatic token must not overwrite the latest"
        )
    }

    func testAutomaticPushTokenSequenceDoesNotAllowNewClaimDuringLatestOperation() {
        let sequence = AutomaticPushTokenSequence()
        let firstGeneration = sequence.claimGeneration()
        let firstOperationStarted = expectation(description: "first operation started")
        let releaseFirstOperation = DispatchSemaphore(value: 0)
        let newerGenerationClaimed = DispatchSemaphore(value: 0)
        // Guarantees the blocked global-queue worker is released even if this test fails
        // or times out before the explicit `signal()` below runs.
        defer { releaseFirstOperation.signal() }

        DispatchQueue.global().async {
            sequence.performIfLatest(firstGeneration) {
                firstOperationStarted.fulfill()
                releaseFirstOperation.wait()
            }
        }
        wait(for: [firstOperationStarted], timeout: 1.0)

        DispatchQueue.global().async {
            _ = sequence.claimGeneration()
            newerGenerationClaimed.signal()
        }
        let claimBeforeOperationFinished = newerGenerationClaimed.wait(
            timeout: .now() + 0.1
        )
        releaseFirstOperation.signal()
        let claimAfterOperationFinished = newerGenerationClaimed.wait(
            timeout: .now() + 1.0
        )

        XCTAssertEqual(claimBeforeOperationFinished, .timedOut)
        XCTAssertEqual(claimAfterOperationFinished, .success)
    }

    // MARK: test set external id

    func testSetExternalId() async throws {
        seedInitializedRecording()
        _ = klaviyo.set(externalId: "foo")

        try await waitForCondition { IdentityStore.shared.current.externalId == "foo" }
        XCTAssertEqual(IdentityStore.shared.current.externalId, "foo")
    }

    // MARK: test handle push notification

    func testHandlePushNotification() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
        let push_body = ["body": [
            "_k": [
                "foo": "bar"
            ]
        ]]
        let response = try UNNotificationResponse.with(userInfo: push_body)
        let handled = klaviyo.handle(notificationResponse: response) {
            callback.fulfill()
        }

        await fulfillment(of: [callback], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertTrue(handled)
        let opened = openedPushEvents()
        XCTAssertEqual(opened.count, 1, "body tap tracks exactly one opened push")
        XCTAssertEqual(opened.first?.priority, .high)
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
        IdentityStore.shared.update(ProfileData(
            email: "foo@foo.com",
            phoneNumber: "555BLOB",
            externalId: "my_test_id",
            anonymousId: environment.uuid().uuidString
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "blobtoken",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        let klaviyo = KlaviyoSDK()
        XCTAssertEqual("foo@foo.com", klaviyo.email)
        XCTAssertEqual("555BLOB", klaviyo.phoneNumber)
        XCTAssertEqual("blobtoken", klaviyo.pushToken)
        XCTAssertEqual("my_test_id", klaviyo.externalId)
    }

    // MARK: tracking link handling

    func testHandleUniversalTrackingLinkReturnsTrueForHTTPS() throws {
        let url = try XCTUnwrap(URL(string: "https://email.klaviyo.com/u/tracking/link"))
        let result = klaviyo.handleUniversalTrackingLink(url)
        XCTAssertTrue(result, "Should return true for valid HTTPS universal tracking link")
    }

    func testHandleUniversalTrackingLinkWithHTTPURL() throws {
        let url = try XCTUnwrap(URL(string: "http://email.klaviyo.com/u/tracking/link"))
        let result = klaviyo.handleUniversalTrackingLink(url)
        XCTAssertTrue(result, "Should return true for valid HTTP universal tracking link")
    }

    func testHandleUniversalTrackingLinkWithDifferentPath() throws {
        let url = try XCTUnwrap(URL(string: "https://manage.kmail-lists.com/u/campaign/12345"))
        let result = klaviyo.handleUniversalTrackingLink(url)
        XCTAssertTrue(result, "Should return true for universal tracking link with different domain")
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
        let result = klaviyo.handleUniversalTrackingLink(url)
        XCTAssertTrue(result, "Should return true for universal tracking link with query parameters")
    }

    func testHandleUniversalTrackingLinkWithFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://email.klaviyo.com/u/tracking/link#section"))
        let result = klaviyo.handleUniversalTrackingLink(url)
        XCTAssertTrue(result, "Should return true for universal tracking link with fragment")
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

    func testKlaviyoSDKInitRegistersAggregateEventDispatch() async throws {
        seedInitializedRecording()
        _ = KlaviyoSDK() // registration happens in init
        let payload = Data("agg".utf8)
        EventDispatcher.shared.dispatch(.aggregateEvent(payload))

        try await waitForCondition {
            self.recordedRequests().contains { request in
                if case .aggregateEvent = request.endpoint { return true }
                return false
            }
        }
        let hasAggregate = recordedRequests().contains { request in
            if case .aggregateEvent = request.endpoint { return true }
            return false
        }
        XCTAssertTrue(hasAggregate)
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

    func testHandleActionButtonTap_DeepLinkWithAllProperties() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
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

        let response = try UNNotificationResponse.with(userInfo: userInfo, actionIdentifier: actionId)
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertTrue(handled, "Should handle Klaviyo notification with action button")

        let opened = try XCTUnwrap(openedPushEvents().first)
        XCTAssertEqual(opened.priority, .high, "Opened-push event must be high priority")
        XCTAssertEqual(stringProperty(opened.attributes, "Button Label"), buttonLabel)
        XCTAssertEqual(stringProperty(opened.attributes, "Button ID"), actionId)
        XCTAssertEqual(stringProperty(opened.attributes, "Button Action"), "Deep Link")
        XCTAssertEqual(stringProperty(opened.attributes, "Button Link"), actionURL.absoluteString)
        let body = (opened.attributes.properties.value as? [String: Any])?["body"] as? [String: Any]
        XCTAssertEqual(body?["_k"] as? String, "test_notification_001")
    }

    func testHandleActionButtonTap_OpenAppWithoutURL() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
        let actionId = "com.klaviyo.test.open"
        let buttonLabel = "Open App"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_notification_002",
                "action_buttons": [
                    ["id": actionId, "label": buttonLabel, "action": "open_app"]
                ]
            ]
        ]

        let response = try UNNotificationResponse.with(userInfo: userInfo, actionIdentifier: actionId)
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertTrue(handled)

        let opened = try XCTUnwrap(openedPushEvents().first)
        XCTAssertEqual(opened.priority, .high)
        XCTAssertEqual(stringProperty(opened.attributes, "Button Label"), buttonLabel)
        XCTAssertEqual(stringProperty(opened.attributes, "Button ID"), actionId)
        XCTAssertEqual(stringProperty(opened.attributes, "Button Action"), "Open App")
        XCTAssertNil(stringProperty(opened.attributes, "Button Link"), "openApp has no Button Link")
    }

    func testHandleActionButtonTap_NotTriggeredOnBodyTap() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
        let actionId = "com.klaviyo.test.button"
        let buttonLabel = "Tap Me"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_notification_004",
                "action_buttons": [
                    ["id": actionId, "label": buttonLabel, "action": "open_app"]
                ]
            ]
        ]

        let response = try UNNotificationResponse.with(
            userInfo: userInfo,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertTrue(handled)

        let opened = try XCTUnwrap(openedPushEvents().first)
        XCTAssertEqual(opened.priority, .high)
        XCTAssertNil(stringProperty(opened.attributes, "Button ID"), "body tap has no Button ID")
        XCTAssertNil(stringProperty(opened.attributes, "Button Label"), "body tap has no Button Label")
        XCTAssertNil(stringProperty(opened.attributes, "Button Action"), "body tap has no Button Action")
        XCTAssertNil(stringProperty(opened.attributes, "Button Link"), "body tap has no Button Link")
    }

    // MARK: - Double-track guard

    func testHandleShortCircuitsWhenAutoTracked() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "completion is called")
        let pushBody: [AnyHashable: Any] = ["body": ["_k": ["foo": "bar"]]]
        let response = try UNNotificationResponse.with(userInfo: pushBody)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)

        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback], timeout: 1.0)
        // Yield control briefly so any async enqueue work (if the guard were absent) can run.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(handled)
        XCTAssertTrue(openedPushEvents().isEmpty, "auto-tracked response must not re-enqueue")
    }

    func testProxyThenManualHandleEmitsOneEvent() async throws {
        seedInitializedRecording()
        let proxyCallback = XCTestExpectation(description: "proxy completion fires")
        let manualCallback = XCTestExpectation(description: "manual completion fires")
        let pushBody: [AnyHashable: Any] = ["body": ["_k": ["foo": "bar"]]]
        let response = try UNNotificationResponse.with(userInfo: pushBody)

        // proxy path
        let wasTracked = klaviyo.handle(notificationResponse: response) { proxyCallback.fulfill() }
        XCTAssertTrue(wasTracked)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)
        await fulfillment(of: [proxyCallback], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertEqual(openedPushEvents().count, 1, "proxy call emits exactly one _openedPush")

        // manual host path for same response
        let handled2 = klaviyo.handle(notificationResponse: response) { manualCallback.fulfill() }
        XCTAssertTrue(handled2)
        await fulfillment(of: [manualCallback], timeout: 1.0)
        // Yield so any spurious enqueue work can run before the assertion.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(openedPushEvents().count, 1, "manual handle must not emit a second event")
    }

    func testHandleShortCircuitSuppressesDeepLinkDispatch() throws {
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

        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        wait(for: [callback, noDeepLink], timeout: 1.0)
        XCTAssertTrue(handled)
    }

    func testProxyThenManualHandleDedupsViaTm() async throws {
        seedInitializedRecording()
        let proxyCallback = XCTestExpectation(description: "proxy completion fires")
        let manualCallback = XCTestExpectation(description: "manual completion fires")
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

        let wasTracked = klaviyo.handle(notificationResponse: response) { proxyCallback.fulfill() }
        XCTAssertTrue(wasTracked)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)
        await fulfillment(of: [proxyCallback], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertEqual(openedPushEvents().count, 1, "proxy call emits exactly one _openedPush")

        let handled2 = klaviyo.handle(notificationResponse: response) { manualCallback.fulfill() }
        XCTAssertTrue(handled2)
        await fulfillment(of: [manualCallback], timeout: 1.0)
        // Yield so any spurious enqueue work can run before the assertion.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(openedPushEvents().count, 1, "manual handle must not emit a second event")
    }

    func testHandleShortCircuitsForActionButtonTapWhenAutoTracked() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "completion is called")
        let actionId = "com.klaviyo.test.button.dedup"
        let pushBody: [AnyHashable: Any] = [
            "body": [
                "_k": "test_dedup_action",
                "action_buttons": [["id": actionId, "label": "Tap Me", "action": "open_app"]]
            ]
        ]
        let response = try UNNotificationResponse.with(userInfo: pushBody, actionIdentifier: actionId)
        KlaviyoNotificationDelegate.shared.markAsAutoTracked(dedupKey: response.klaviyoDedupKey)

        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback], timeout: 1.0)
        // Yield so any spurious enqueue work can run before the assertion.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(handled)
        XCTAssertTrue(openedPushEvents().isEmpty, "auto-tracked action tap must not re-enqueue")
    }

    // MARK: - web_url tests

    // Deep link / web URL resolution routes through `DeepLinkManager`
    // (`openDeepLinkSpy`/`openExternalURLSpy`); the `$opened_push` event track routes through
    // `KlaviyoCommands.enqueueEvent` → the recording `QueueStore`.

    func testHandleBodyTap_WebUrlDispatchesOpenWebUrl() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
        let webURL = try XCTUnwrap(URL(string: "https://example.com/sale"))

        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "test_web_url"],
            "web_url": webURL.absoluteString
        ]

        let externalUrlInvoked = XCTestExpectation(description: "openExternalURL invoked")
        DeepLinkManager.openExternalURLSpy = { dispatchedUrl in
            XCTAssertEqual(dispatchedUrl, webURL)
            externalUrlInvoked.fulfill()
        }

        let response = try UNNotificationResponse.with(userInfo: userInfo)
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback, externalUrlInvoked], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertTrue(handled)
        XCTAssertFalse(openedPushEvents().isEmpty, "body tap enqueues an opened-push event")
    }

    func testHandleBodyTap_DeepLinkUnchangedWhenWebUrlAbsent() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
        let deepURL = try XCTUnwrap(URL(string: "myapp://path"))

        let userInfo: [AnyHashable: Any] = [
            "body": ["_k": "test_deep_link_regression"],
            "url": deepURL.absoluteString
        ]

        let deepLinkInvoked = XCTestExpectation(description: "openDeepLink invoked")
        DeepLinkManager.openDeepLinkSpy = { dispatchedUrl in
            XCTAssertEqual(dispatchedUrl, deepURL)
            deepLinkInvoked.fulfill()
        }

        let response = try UNNotificationResponse.with(userInfo: userInfo)
        _ = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback, deepLinkInvoked], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertFalse(openedPushEvents().isEmpty, "body tap enqueues an opened-push event")
    }

    func testHandleBodyTap_DeepLinkTakesPrecedenceOverWebUrl() throws {
        // Defensive: if backend ever ships both web_url and url, the deep link wins so
        // the user stays in the host app.
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
        _ = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        wait(for: [callback, deepLinkInvoked], timeout: 1.0)
        wait(for: [externalUrlNotInvoked], timeout: 0.3)
    }

    func testHandleActionButtonTap_OpenUrlButton() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
        let actionURL = try XCTUnwrap(URL(string: "https://example.com/promo"))
        let actionId = "com.klaviyo.test.web"
        let buttonLabel = "Visit Site"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_open_url_button",
                "action_buttons": [
                    ["id": actionId, "label": buttonLabel, "action": "open_url", "url": actionURL.absoluteString]
                ]
            ]
        ]

        let externalUrlInvoked = XCTestExpectation(description: "openExternalURL invoked")
        DeepLinkManager.openExternalURLSpy = { dispatchedUrl in
            XCTAssertEqual(dispatchedUrl, actionURL)
            externalUrlInvoked.fulfill()
        }

        let response = try UNNotificationResponse.with(userInfo: userInfo, actionIdentifier: actionId)
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback, externalUrlInvoked], timeout: 1.0)
        try await waitForOpenedPush()
        XCTAssertTrue(handled)

        let opened = try XCTUnwrap(openedPushEvents().first)
        XCTAssertEqual(stringProperty(opened.attributes, "Button Action"), "Open URL")
        XCTAssertEqual(stringProperty(opened.attributes, "Button Link"), actionURL.absoluteString)
    }

    func testHandleActionButtonTap_OpenUrlButtonWithBlockedSchemeDoesNotDispatch() async throws {
        seedInitializedRecording()
        let callback = XCTestExpectation(description: "callback is made")
        let actionURL = try XCTUnwrap(URL(string: "javascript:alert(1)"))
        let actionId = "com.klaviyo.test.blocked"
        let buttonLabel = "Bad Button"

        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": "test_open_url_blocked",
                "action_buttons": [
                    ["id": actionId, "label": buttonLabel, "action": "open_url", "url": actionURL.absoluteString]
                ]
            ]
        ]

        let externalUrlNotInvoked = XCTestExpectation(description: "openExternalURL must not be invoked for blocked scheme")
        externalUrlNotInvoked.isInverted = true
        DeepLinkManager.openExternalURLSpy = { _ in externalUrlNotInvoked.fulfill() }

        let response = try UNNotificationResponse.with(userInfo: userInfo, actionIdentifier: actionId)
        let handled = klaviyo.handle(notificationResponse: response) { callback.fulfill() }

        await fulfillment(of: [callback], timeout: 1.0)
        wait(for: [externalUrlNotInvoked], timeout: 0.3)
        try await waitForOpenedPush()
        XCTAssertTrue(handled)
        XCTAssertFalse(openedPushEvents().isEmpty, "tap is tracked even when the scheme is blocked")
    }

    // MARK: - Poll helpers

    /// Polls `condition` until true or timeout (bridges the facade's main-queue hop +
    /// orchestration's unstructured tasks). Fails loudly on timeout via the shared helper.
    private func waitForCondition(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async throws {
        try await waitForConditionOrFail(timeout: timeout, file: file, line: line) { condition() }
    }

    /// Fulfills `expectation` once `condition` holds, re-scheduling on the main queue.
    private func pollOnMain(_ expectation: XCTestExpectation, _ condition: @escaping () -> Bool) {
        if condition() {
            expectation.fulfill()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.pollOnMain(expectation, condition)
            }
        }
    }
}
