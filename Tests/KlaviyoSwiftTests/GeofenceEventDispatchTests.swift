//
//  GeofenceEventDispatchTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import XCTest

@MainActor
final class GeofenceEventDispatchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    // MARK: - Geofence Event Tests

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

        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let apiKey = "TEST123"

        // Expect: the store transitions to initialized with the geofence api key.
        let initialized = XCTestExpectation(description: "SDK initialized with the geofence api key")
        initialized.assertForOverFulfill = false
        let cancellable = testStore.state.sink { state in
            if state.initalizationState == .initialized, state.apiKey == apiKey {
                initialized.fulfill()
            }
        }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event while uninitialized
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: apiKey)
        await fulfillment(of: [initialized], timeout: 1.0)

        // Then: SDK is initialized and the api key is set
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.initalizationState, .initialized, "SDK should be initialized")
        XCTAssertEqual(currentState.apiKey, apiKey, "API key should be set")
    }

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

        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let apiKey = initialState.apiKey!

        // Expect: the prioritized geofence event forces a flush, draining the queue.
        let flushed = XCTestExpectation(description: "queue flushed after geofence event")
        flushed.assertForOverFulfill = false
        let cancellable = testStore.state.sink { state in
            if state.queue.isEmpty {
                flushed.fulfill()
            }
        }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event with matching API key
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: apiKey)
        await fulfillment(of: [flushed], timeout: 1.0)

        // Then: queue is flushed (items moved out and queue is empty)
        XCTAssertTrue(
            testStore.state.value.queue.isEmpty,
            "Queue should be empty after a geofence event forces a flush"
        )
    }

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

        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let differentApiKey = "DIFFERENT_KEY"

        // Expect: NO state change — the api-key mismatch guard returns before any dispatch.
        // An inverted expectation passes only if the store never emits a change.
        let noStateChange = XCTestExpectation(description: "no state change when API key does not match")
        noStateChange.isInverted = true
        let cancellable = testStore.state
            .dropFirst() // ignore the CurrentValueSubject replay of the initial state
            .sink { _ in noStateChange.fulfill() }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event with a non-matching API key
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: differentApiKey)
        await fulfillment(of: [noStateChange], timeout: 0.5)

        // Then: SDK was not re-initialized and the event was not enqueued
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.apiKey, "EXISTING_KEY", "API key should remain unchanged")
        XCTAssertEqual(
            currentState.pendingRequests.count, 0,
            "Event should not be enqueued when API key doesn't match"
        )
        XCTAssertEqual(currentState.queue.count, 0, "Queue should remain empty")
    }

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

        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"]
        )
        let matchingApiKey = "MATCHING_KEY"

        // Expect: the event is processed — the forced flush drains the queue into requestsInFlight.
        let processed = XCTestExpectation(description: "geofence event processed (queued then flushed)")
        processed.assertForOverFulfill = false
        let cancellable = testStore.state.sink { state in
            if state.queue.isEmpty || !state.requestsInFlight.isEmpty {
                processed.fulfill()
            }
        }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event with matching API key
        await GeofenceEventDispatch.dispatch(event: geofenceEvent, apiKey: matchingApiKey)
        await fulfillment(of: [processed], timeout: 1.0)

        // Then: event was processed (either still queued behind the flush or already in flight)
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.apiKey, "MATCHING_KEY", "API key should remain unchanged")
        XCTAssertTrue(
            currentState.queue.isEmpty || !currentState.requestsInFlight.isEmpty,
            "Event should be processed (either in queue or in flight)"
        )
    }
}
