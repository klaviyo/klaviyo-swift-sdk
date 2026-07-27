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
        klaviyoSwiftEnvironment.stateChangePublisher = { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() }
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

    /// An initialized state seeded with a couple of queued requests, for the flush/enqueue cases.
    private func initializedStateWithQueuedItems(apiKey: String) -> KlaviyoState {
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
        state.queue = [request1, request2]
        return state
    }

    // MARK: - Geofence Event Tests

    func testCreateGeofenceEvent_initializesSDKAndSendsEventWhenUninitialized() async throws {
        // Given: SDK is uninitialized
        let testStore = makeTestStore(initialState: KlaviyoState(queue: [], initalizationState: .uninitialized))
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
        let testStore = makeTestStore(initialState: initializedStateWithQueuedItems(apiKey: apiKey))

        // Expect: the prioritized geofence event forces a flush, draining the queue.
        let flushed = XCTestExpectation(description: "queue flushed after geofence event")
        flushed.assertForOverFulfill = false
        let cancellable = testStore.state.sink { state in
            if state.queue.isEmpty { flushed.fulfill() }
        }
        defer { cancellable.cancel() }

        // When: dispatch a geofence event with matching API key
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)
        await fulfillment(of: [flushed], timeout: 1.0)

        // Then: queue is flushed (items moved out and queue is empty)
        XCTAssertTrue(testStore.state.value.queue.isEmpty, "Queue should be empty after a geofence event forces a flush")
    }

    func testCreateGeofenceEvent_ignoresEventWhenAPIKeyDoesNotMatch() async throws {
        // Given: SDK is initialized with a different API key
        var initialState = INITIALIZED_TEST_STATE()
        initialState.apiKey = "EXISTING_KEY"
        initialState.flushing = false
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
        XCTAssertEqual(currentState.pendingRequests.count, 0, "Event should not be enqueued when API key doesn't match")
        XCTAssertEqual(currentState.queue.count, 0, "Queue should remain empty")
    }

    func testCreateGeofenceEvent_enqueuesEventWhenAPIKeyMatches() async throws {
        // Given: SDK is initialized with matching API key and items in the queue
        let apiKey = "MATCHING_KEY"
        let testStore = makeTestStore(initialState: initializedStateWithQueuedItems(apiKey: apiKey))

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
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)
        await fulfillment(of: [processed], timeout: 1.0)

        // Then: event was processed (either still queued behind the flush or already in flight)
        let currentState = testStore.state.value
        XCTAssertEqual(currentState.apiKey, "MATCHING_KEY", "API key should remain unchanged")
        XCTAssertTrue(
            currentState.queue.isEmpty || !currentState.requestsInFlight.isEmpty,
            "Event should be processed (either in queue or in flight)"
        )
    }

    // MARK: - Diagnostic: SharedStoreMirror bootstrap gap (Cursor #650, Medium)

    /// Demonstrates the coupling gap flagged on PR #650: `GeofenceEventDispatch.dispatch`
    /// initializes the reducer directly, bypassing `KlaviyoSDK.initialize(with:)` — the only
    /// place `SharedStoreMirror.setup()` runs. So the reducer becomes `.initialized` while the
    /// KlaviyoCore shared stores that other modules read (`SDKConfigStore`/`IdentityStore`) stay
    /// empty.
    ///
    /// Semantics: this test PASSES while the bug is present (shared store empty despite an
    /// initialized reducer). A fix — calling `SharedStoreMirror.setup()` inside `dispatch` before
    /// the `.initialize` send — makes the final assertion fail; flip it to
    /// `XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)` at that point.
    func test_diagnostic_geofenceBootstrap_leavesSharedStoresEmpty() async throws {
        // Given: mirror detached + shared stores cleared; host never called initialize(with:)
        SharedStoreMirror.reset()
        defer { SharedStoreMirror.reset() } // don't leak the mirror/store state into other tests

        let apiKey = "TEST123"
        let testStore = makeTestStore(
            initialState: KlaviyoState(queue: [], initalizationState: .uninitialized)
        )

        // Expect the reducer to reach .initialized purely via the geofence bootstrap path.
        let initialized = XCTestExpectation(description: "reducer initialized via geofence bootstrap")
        initialized.assertForOverFulfill = false
        let cancellable = testStore.state.sink { state in
            if state.initalizationState == .initialized, state.apiKey == apiKey {
                initialized.fulfill()
            }
        }
        defer { cancellable.cancel() }

        // When: SDK is bootstrapped ONLY through the geofence entry point
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)
        await fulfillment(of: [initialized], timeout: 1.0)

        // Then: reducer is initialized...
        XCTAssertEqual(testStore.state.value.initalizationState, .initialized)
        XCTAssertEqual(testStore.state.value.apiKey, apiKey)

        // ...but the shared store other modules read is still empty → gap confirmed.
        XCTAssertNil(
            SDKConfigStore.shared.current.apiKey,
            "BUG CONFIRMED: geofence bootstrap initialized the reducer but never set up SharedStoreMirror, "
                + "so SDKConfigStore stays empty for KlaviyoLocation/KlaviyoForms."
        )
    }
}
