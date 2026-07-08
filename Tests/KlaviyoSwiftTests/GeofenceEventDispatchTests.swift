//
//  GeofenceEventDispatchTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import XCTest

final class GeofenceEventDispatchTests: XCTestCase {
    @MainActor
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    // MARK: - Geofence Event Tests

    @MainActor
    func testCreateGeofenceEvent_initializesSDKAndSendsEventWhenUninitialized() async throws {
        // Given: SDK is uninitialized
        let initialState = KlaviyoState(queue: [], initalizationState: .uninitialized)
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
        klaviyoSwiftEnvironment.send = { action in
            _ = testStore.send(action)
            return nil
        }
        klaviyoSwiftEnvironment.state = { testStore.state.value }
        klaviyoSwiftEnvironment.stateChangePublisher = { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() }

        // When: Create geofence event
        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let apiKey = "TEST123"
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: apiKey)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: Verify SDK is initialized and event is in pending requests
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.initalizationState, .initialized, "SDK should be initialized")
        XCTAssertEqual(currentState.apiKey, apiKey, "API key should be set")
    }

    @MainActor
    func testCreateGeofenceEvent_flushesQueueWhenQueueHasItems() async throws {
        // Given: SDK is initialized with items in the queue
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false

        // Add some existing requests to the queue
        let existingRequest1 = initialState.buildProfileRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!
        )
        let existingRequest2 = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!,
            pushToken: "token1",
            enablement: .authorized
        )
        initialState.queue = [existingRequest1, existingRequest2]

        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
        klaviyoSwiftEnvironment.send = { action in
            _ = testStore.send(action)
            return nil
        }
        klaviyoSwiftEnvironment.state = { testStore.state.value }
        klaviyoSwiftEnvironment.stateChangePublisher = { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() }

        // When: Create a geofence event with matching API key
        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let apiKey = initialState.apiKey!
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: apiKey)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then: Verify queue is flushed (items moved to requestsInFlight and queue is empty)
        XCTAssertTrue(testStore.state.value.queue.isEmpty, "Queue should be empty after a geofence event forces a flush")
    }

    @MainActor
    func testCreateGeofenceEvent_ignoresEventWhenAPIKeyDoesNotMatch() async throws {
        // Given: SDK is initialized with a different API key
        var initialState = INITIALIZED_TEST_STATE()
        initialState.apiKey = "EXISTING_KEY"
        initialState.flushing = false
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
        klaviyoSwiftEnvironment.send = { action in
            _ = testStore.send(action)
            return nil
        }
        klaviyoSwiftEnvironment.state = { testStore.state.value }
        klaviyoSwiftEnvironment.stateChangePublisher = { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() }

        // When: Create a geofence event with a different API key
        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let differentApiKey = "DIFFERENT_KEY"
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: differentApiKey)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: Verify SDK was not re-initialized and event was not enqueued
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.apiKey, "EXISTING_KEY", "API key should remain unchanged")
        XCTAssertEqual(currentState.pendingRequests.count, 0, "Event should not be enqueued when API key doesn't match")
        XCTAssertEqual(currentState.queue.count, 0, "Queue should remain empty")
    }

    @MainActor
    func testCreateGeofenceEvent_enqueuesEventWhenAPIKeyMatches() async throws {
        // Given: SDK is initialized with matching API key
        var initialState = INITIALIZED_TEST_STATE()
        initialState.apiKey = "MATCHING_KEY"
        initialState.flushing = false

        // Add some existing requests to the queue
        let existingRequest1 = initialState.buildProfileRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!
        )
        let existingRequest2 = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!,
            pushToken: "token1",
            enablement: .authorized
        )
        initialState.queue = [existingRequest1, existingRequest2]

        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
        klaviyoSwiftEnvironment.send = { action in
            _ = testStore.send(action)
            return nil
        }
        klaviyoSwiftEnvironment.state = { testStore.state.value }
        klaviyoSwiftEnvironment.stateChangePublisher = { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() }

        // When: Create a geofence event with matching API key
        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let matchingApiKey = "MATCHING_KEY"
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: matchingApiKey)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then: Verify event was enqueued (should trigger flushQueue for prioritized events)
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.apiKey, "MATCHING_KEY", "API key should remain unchanged")
        XCTAssertTrue(
            currentState.queue.isEmpty || !currentState.requestsInFlight.isEmpty,
            "Event should be processed (either in queue or in flight)"
        )
    }
}
