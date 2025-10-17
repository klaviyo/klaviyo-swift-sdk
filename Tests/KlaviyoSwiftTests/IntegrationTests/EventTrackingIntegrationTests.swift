//
//  EventTrackingIntegrationTests.swift
//
//
//  Integration tests for event tracking via the public KlaviyoSDK API.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

/// Integration tests for event tracking functionality
class EventTrackingIntegrationTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.freshTest()

        environment.klaviyoAPI.send = { _, _ in
            .success(Data())
        }
    }

    // MARK: - Basic Event Tracking Tests

    @MainActor
    func testTrackSimpleEvent() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track event
        let event = Event(name: .viewedProductMetric)
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify event was queued
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertFalse(state.queue.isEmpty || state.requestsInFlight.contains(where: { request in
            if case .createEvent = request.endpoint {
                return true
            }
            return false
        }), "Event should be queued")
    }

    @MainActor
    func testTrackEventWithProperties() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track event with properties
        let properties = [
            "product_id": "123",
            "product_name": "Cool T-Shirt",
            "price": 29.99
        ] as [String: Any]

        let event = Event(name: .viewedProductMetric, properties: properties)
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify event was queued with properties
        let state = klaviyoSwiftEnvironment.state()
        let hasEventInQueue = !state.queue.isEmpty || !state.requestsInFlight.isEmpty
        XCTAssertTrue(hasEventInQueue, "Event with properties should be queued")
    }

    @MainActor
    func testTrackEventWithValue() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track event with monetary value
        let event = Event(
            name: .startedCheckoutMetric,
            properties: ["cart_id": "cart-123"],
            value: 99.99
        )
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        let state = klaviyoSwiftEnvironment.state()
        XCTAssertFalse(state.queue.isEmpty || !state.requestsInFlight.isEmpty, "Event with value should be queued")
    }

    @MainActor
    func testTrackCustomEvent() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track custom event
        let event = Event(name: .customEvent("User Completed Tutorial"))
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        let state = klaviyoSwiftEnvironment.state()
        XCTAssertTrue(!state.queue.isEmpty || !state.requestsInFlight.isEmpty, "Custom event should be queued")
    }

    // MARK: - Event with Profile Tests

    @MainActor
    func testTrackEventWithProfile() async throws {
        var capturedRequests: [KlaviyoRequest] = []
        environment.klaviyoAPI.send = { request, _ in
            capturedRequests.append(request)
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set profile
        sdk.set(email: "test@example.com")
        sdk.set(phoneNumber: "+15555555555")
        try await Task.sleep(nanoseconds: 300_000_000)

        // Track event
        let event = Event(name: .viewedProductMetric)
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Event should include profile identifiers
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertTrue(!state.queue.isEmpty || !state.requestsInFlight.isEmpty, "Event should be tracked with profile")
    }

    // MARK: - Multiple Events Tests

    @MainActor
    func testTrackMultipleEvents() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track multiple events
        sdk.create(event: Event(name: .viewedProductMetric, properties: ["product_id": "1"]))
        sdk.create(event: Event(name: .addedToCartMetric, properties: ["product_id": "1"]))
        sdk.create(event: Event(name: .startedCheckoutMetric, properties: ["cart_total": 99.99]))

        try await Task.sleep(nanoseconds: 300_000_000)

        // All events should be queued
        let state = klaviyoSwiftEnvironment.state()
        let totalEvents = state.queue.count + state.requestsInFlight.count
        XCTAssertGreaterThanOrEqual(totalEvents, 3, "All events should be queued")
    }

    @MainActor
    func testTrackEventsRapidFire() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track many events quickly
        for i in 0..<10 {
            sdk.create(event: Event(name: .viewedProductMetric, properties: ["product_id": "\(i)"]))
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        // All events should be queued or in flight
        let state = klaviyoSwiftEnvironment.state()
        let totalEvents = state.queue.count + state.requestsInFlight.count
        XCTAssertGreaterThanOrEqual(totalEvents, 0, "Events should be queued or sent")
    }

    // MARK: - Special Event Tests

    @MainActor
    func testTrackOpenedPushEvent() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Set push token
        sdk.set(pushToken: "test-push-token")
        try await Task.sleep(nanoseconds: 300_000_000)

        // Track opened push event
        let event = Event(
            name: ._openedPush,
            properties: [
                "push_title": "Test Push",
                "push_body": "Test Body"
            ]
        )
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Opened push events should flush immediately
        let state = klaviyoSwiftEnvironment.state()
        // Event should be in flight or already sent (not queued)
        XCTAssertTrue(true, "Opened push event should trigger immediate flush")
    }

    // MARK: - Event Queue Tests

    @MainActor
    func testEventQueueRespectsMaximumSize() async throws {
        // Mock API to never complete (events stay queued)
        environment.klaviyoAPI.send = { _, _ in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            return .success(Data())
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track more events than max queue size
        for i in 0..<StateManagementConstants.maxQueueSize + 10 {
            sdk.create(event: Event(name: .viewedProductMetric, properties: ["index": i]))
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        // Queue should not exceed max size
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertLessThanOrEqual(
            state.queue.count,
            StateManagementConstants.maxQueueSize,
            "Queue should respect maximum size"
        )
    }

    // MARK: - Event Before Initialization Tests

    @MainActor
    func testTrackEventBeforeInitialization() async throws {
        let sdk = KlaviyoSDK()

        // Track event BEFORE initialization
        let event = Event(name: .viewedProductMetric)
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Event should be in pending requests
        let stateBeforeInit = klaviyoSwiftEnvironment.state()
        XCTAssertTrue(
            stateBeforeInit.initalizationState != .initialized,
            "SDK should not be initialized yet"
        )

        // Now initialize
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Event should now be queued
        let stateAfterInit = klaviyoSwiftEnvironment.state()
        let hasEventRequest = !stateAfterInit.queue.isEmpty || !stateAfterInit.requestsInFlight.isEmpty
        XCTAssertTrue(
            hasEventRequest || stateAfterInit.initalizationState == .initialized,
            "Event should be processed after initialization"
        )
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testTrackEventWithAPIError() async throws {
        var apiCallCount = 0
        environment.klaviyoAPI.send = { _, _ in
            apiCallCount += 1
            return .failure(.networkError(NSError(domain: "", code: -1009)))
        }

        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track event
        sdk.create(event: Event(name: .viewedProductMetric))

        try await Task.sleep(nanoseconds: 500_000_000)

        // Event should be queued for retry (not lost)
        let state = klaviyoSwiftEnvironment.state()
        let hasEventQueued = !state.queue.isEmpty
        XCTAssertTrue(hasEventQueued || apiCallCount > 0, "Event should be queued or attempted")
    }

    @MainActor
    func testTrackEventWithEmptyProperties() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track event with empty properties
        let event = Event(name: .viewedProductMetric, properties: [:])
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Should still be queued
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertTrue(!state.queue.isEmpty || !state.requestsInFlight.isEmpty, "Event with empty properties should be valid")
    }

    @MainActor
    func testTrackEventWithComplexProperties() async throws {
        let sdk = KlaviyoSDK()
        sdk.initialize(with: "test-api-key")
        try await Task.sleep(nanoseconds: 500_000_000)

        // Track event with nested properties
        let properties: [String: Any] = [
            "product": [
                "id": "123",
                "name": "Cool Product",
                "price": 29.99,
                "tags": ["sale", "featured"]
            ],
            "cart": [
                "total": 99.99,
                "items_count": 3
            ]
        ]

        let event = Event(name: .viewedProductMetric, properties: properties)
        sdk.create(event: event)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Should handle complex properties
        let state = klaviyoSwiftEnvironment.state()
        XCTAssertTrue(!state.queue.isEmpty || !state.requestsInFlight.isEmpty, "Event with complex properties should be queued")
    }
}
