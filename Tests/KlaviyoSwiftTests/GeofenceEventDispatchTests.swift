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
        let request1 = state.buildProfileRequest(apiKey: apiKey, anonymousId: state.anonymousId!)
        let request2 = state.buildTokenRequest(
            apiKey: apiKey,
            anonymousId: state.anonymousId!,
            pushToken: "token1",
            enablement: .authorized
        )
        let readQueue = seedTestQueueStore(initial: [request1, request2])
        return (state, readQueue)
    }

    // MARK: - Geofence Event Tests

    func testCreateGeofenceEvent_initializesSDKAndSendsEventWhenUninitialized() async throws {
        // Given: SDK is uninitialized
        let testStore = makeTestStore(initialState: KlaviyoState(initalizationState: .uninitialized))
        let apiKey = "TEST123"
        seedTestQueueStore()

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
        // Seed the canonical stores so the env RequestQueue's flush gate (apiKey) passes and the
        // enqueued geofence event resolves against a real identity.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(state.identity)
        IdentityStore.shared.updatePushToken(state.pushTokenData)
        _ = makeTestStore(initialState: state)

        // When: dispatch a geofence event with matching API key. The prioritized event forces an
        // immediate flush on the Core RequestQueue actor, which drains the durable QueueStore and
        // sends through the test transport.
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)

        // Then: the durable queue drains (the actor flush is async/off-store, so poll it).
        try await waitUntilQueueEmpty(readQueue)
    }

    /// Polls the durable QueueStore until it drains, since the Core `RequestQueue` actor's flush runs
    /// asynchronously off the reducer store (no reducer state change to observe).
    private func waitUntilQueueEmpty(
        _ readQueue: () -> [KlaviyoRequest],
        timeout: TimeInterval = 2.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if readQueue().isEmpty { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(readQueue().isEmpty, "Queue should be empty after a geofence event forces a flush")
    }

    func testCreateGeofenceEvent_ignoresEventWhenAPIKeyDoesNotMatch() async throws {
        // Given: SDK is initialized with a different API key
        var initialState = INITIALIZED_TEST_STATE()
        initialState.apiKey = "EXISTING_KEY"
        let readQueue = seedTestQueueStore()
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
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(state.identity)
        IdentityStore.shared.updatePushToken(state.pushTokenData)
        let testStore = makeTestStore(initialState: state)

        // When: dispatch a geofence event with matching API key. The prioritized event is enqueued
        // and forces an immediate flush on the Core RequestQueue actor, which drains the queue.
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)

        // Then: the event was processed — the forced flush drains the durable queue (async/off-store).
        try await waitUntilQueueEmpty(readQueue)
        XCTAssertEqual(testStore.state.value.apiKey, "MATCHING_KEY", "API key should remain unchanged")
    }
}
