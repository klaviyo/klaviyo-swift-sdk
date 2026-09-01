//
//  GeofenceEventDispatchTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import XCTest

@MainActor
final class GeofenceEventDispatchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    // MARK: - Helpers

    /// Wires `klaviyoSwiftEnvironment` to a real store seeded with `initialState`, and returns
    /// the store so tests can observe/assert on its state.
    private func makeTestStore(initialState: KlaviyoState) -> Store<KlaviyoState, KlaviyoAction> {
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
        klaviyoSwiftEnvironment.send = { action in
            _ = testStore.send(action)
            return nil
        }
        klaviyoSwiftEnvironment.state = { testStore.state.value }
        return testStore
    }

    private func makeGeofenceEvent() -> Event {
        // Mirror the priority set by the real producer in
        // KlaviyoLocationManager+CLLocationManagerDelegate.
        Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"],
            priority: .high
        )
    }

    /// An initialized state plus an in-memory QueueStore (for `apiKey`) seeded with a couple of
    /// queued requests, for the flush/enqueue cases. Returns the state and the live-queue getter.
    private func initializedStateWithQueuedItems(
        apiKey: String
    ) -> (state: KlaviyoState, readQueue: () -> [KlaviyoRequest]) {
        var state = INITIALIZED_TEST_STATE()
        state.apiKey = apiKey
        state.flushing = false
        let request1 = state.buildProfileRequest(apiKey: apiKey, anonymousId: state.anonymousId!)
        let request2 = state.buildTokenRequest(
            apiKey: apiKey,
            anonymousId: state.anonymousId!,
            pushToken: "token1",
            enablement: .authorized
        )
        let readQueue = seedTestQueueStore(apiKey: apiKey, initial: [request1, request2])
        return (state, readQueue)
    }

    // MARK: - Geofence Event Tests

    func testCreateGeofenceEvent_initializesSDKAndSendsEventWhenUninitialized() async throws {
        // Given: SDK is uninitialized
        let testStore = makeTestStore(initialState: KlaviyoState(initalizationState: .uninitialized))
        let apiKey = "TEST123"
        seedTestQueueStore(apiKey: apiKey)

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
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)
        await fulfillment(of: [initialized], timeout: 1.0)

        // Then: SDK is initialized and the api key is set
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.initalizationState, .initialized, "SDK should be initialized")
        XCTAssertEqual(currentState.apiKey, apiKey, "API key should be set")
    }

    func testCreateGeofenceEvent_flushesQueueWhenQueueHasItems() async throws {
        // Given: SDK is initialized with items in the queue
        let apiKey = "MATCHING_KEY"
        let (state, readQueue) = initializedStateWithQueuedItems(apiKey: apiKey)
        let testStore = makeTestStore(initialState: state)

        // Expect: the prioritized geofence event forces a flush, draining the queue into in-flight.
        let flushed = XCTestExpectation(description: "queue flushed after geofence event")
        flushed.assertForOverFulfill = false
        let cancellable = testStore.state.sink { state in
            if !state.requestsInFlight.isEmpty, readQueue().isEmpty { flushed.fulfill() }
        }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event with matching API key
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)
        await fulfillment(of: [flushed], timeout: 1.0)

        // Then: the durable queue is drained (items leased into the in-flight set on flush).
        XCTAssertTrue(readQueue().isEmpty, "Queue should be empty after a geofence event forces a flush")
    }

    func testCreateGeofenceEvent_ignoresEventWhenAPIKeyDoesNotMatch() async throws {
        // Given: SDK is initialized with a different API key
        var initialState = INITIALIZED_TEST_STATE()
        initialState.apiKey = "EXISTING_KEY"
        initialState.flushing = false
        let readQueue = seedTestQueueStore(apiKey: "EXISTING_KEY")
        let testStore = makeTestStore(initialState: initialState)

        // Expect: NO state change — the api-key mismatch guard returns before any send.
        // An inverted expectation passes only if the store never emits a change.
        let noStateChange = XCTestExpectation(description: "no state change when API key does not match")
        noStateChange.isInverted = true
        let cancellable = testStore.state
            .dropFirst() // ignore the CurrentValueSubject replay of the initial state
            .sink { _ in noStateChange.fulfill() }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event with a non-matching API key
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: "DIFFERENT_KEY")
        await fulfillment(of: [noStateChange], timeout: 0.5)

        // Then: SDK was not re-initialized and the event was not enqueued
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.apiKey, "EXISTING_KEY", "API key should remain unchanged")
        XCTAssertEqual(readQueue().count, 0, "Queue should remain empty")
    }

    func testCreateGeofenceEvent_enqueuesEventWhenAPIKeyMatches() async throws {
        // Given: SDK is initialized with matching API key and items in the queue
        let apiKey = "MATCHING_KEY"
        let (state, readQueue) = initializedStateWithQueuedItems(apiKey: apiKey)
        let testStore = makeTestStore(initialState: state)

        // Expect: the event is processed — the forced flush drains the queue into requestsInFlight.
        let processed = XCTestExpectation(description: "geofence event processed (queued then flushed)")
        processed.assertForOverFulfill = false
        let cancellable = testStore.state.sink { state in
            if readQueue().isEmpty || !state.requestsInFlight.isEmpty {
                processed.fulfill()
            }
        }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event with matching API key
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)
        await fulfillment(of: [processed], timeout: 1.0)

        // Then: event was processed (either still queued behind the flush or already in flight)
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.apiKey, "MATCHING_KEY", "API key should remain unchanged")
        XCTAssertTrue(
            readQueue().isEmpty || !currentState.requestsInFlight.isEmpty,
            "Event should be processed (either in queue or in flight)"
        )
    }
}
