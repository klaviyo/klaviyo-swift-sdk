//
//  GeofenceEventDispatchTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import Combine
import XCTest

@MainActor
final class GeofenceEventDispatchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        LifecycleState.shared.reset()
        UnattributedBuffer.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    override func tearDown() {
        LifecycleState.shared.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeGeofenceEvent() -> Event {
        // Mirror the priority set by the real producer in
        // KlaviyoLocationManager+CLLocationManagerDelegate.
        Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"],
            priority: .high
        )
    }

    /// Seeds the canonical stores + `LifecycleState` to an initialized state under `apiKey`, with a
    /// couple of queued requests, for the flush/enqueue cases. Returns the live-queue getter.
    @discardableResult
    private func seedInitialized(
        apiKey: String,
        withQueuedItems: Bool = false
    ) -> () -> [KlaviyoRequest] {
        let anonymousId = environment.uuid().uuidString
        let identity = ProfileData(anonymousId: anonymousId)
        let tokenData = PushTokenData(
            pushToken: "token1",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(identity)
        IdentityStore.shared.updatePushToken(tokenData)
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()

        var initial: [KlaviyoRequest] = []
        if withQueuedItems {
            let requestIdentity = RequestIdentity(apiKey: apiKey, anonymousId: anonymousId)
            initial = [
                RequestFactory.profileRequest(identity: requestIdentity, properties: [:]),
                RequestBuilding.resolvedTokenRequest(
                    identity: identity,
                    apiKey: apiKey,
                    anonymousId: anonymousId,
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement,
                    background: tokenData.pushBackground
                )
            ]
        }
        return seedTestQueueStore(initial: initial)
    }

    // MARK: - Geofence Event Tests

    func testCreateGeofenceEvent_initializesSDKAndSendsEventWhenUninitialized() async throws {
        // Given: SDK is uninitialized
        IdentityStore.shared.update(ProfileData(anonymousId: environment.uuid().uuidString))
        let apiKey = "TEST123"
        seedTestQueueStore()

        // When: dispatch a geofence event while uninitialized
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)

        // Then: SDK begins initializing with the geofence api key (the async tail completes it).
        try await waitFor { LifecycleState.shared.current != .uninitialized }
        XCTAssertNotEqual(
            LifecycleState.shared.current, .uninitialized, "SDK should begin initializing"
        )
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey, "API key should be set")
    }

    func testCreateGeofenceEvent_flushesQueueWhenQueueHasItems() async throws {
        // Given: SDK is initialized with items in the queue
        let apiKey = "MATCHING_KEY"
        let readQueue = seedInitialized(apiKey: apiKey, withQueuedItems: true)

        // Capture what the actor sends through the transport.
        let sentRequests = ThreadSafeBox<[KlaviyoRequest]>([])
        environment.klaviyoAPI.send = { request, _ in
            sentRequests.mutate { $0.append(request) }
            return .success(Data())
        }

        // When: dispatch a geofence event with matching API key. The prioritized event forces an
        // immediate flush on the Core RequestQueue actor, which drains the durable QueueStore.
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)

        // Then: the durable queue drains (the actor flush is async/off-store, so poll it).
        try await waitUntilQueueEmpty(readQueue)
        assertGeofenceEventSent(sentRequests.value)
    }

    /// Polls the durable QueueStore until it drains, since the Core `RequestQueue` actor's flush runs
    /// asynchronously off the caller (no synchronous state change to observe).
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
        let readQueue = seedInitialized(apiKey: "EXISTING_KEY")

        // When: dispatch a geofence event with a non-matching API key
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: "DIFFERENT_KEY")
        // Give any (unexpected) async work a beat.
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then: SDK was not re-initialized and the event was not enqueued
        XCTAssertEqual(
            SDKConfigStore.shared.current.apiKey, "EXISTING_KEY", "API key should remain unchanged"
        )
        XCTAssertEqual(readQueue().count, 0, "Queue should remain empty")
    }

    func testCreateGeofenceEvent_ignoresEventWhenAPIKeyDoesNotMatchDuringInitializing() async throws {
        // Given: init has STARTED for key A but not completed (`.initializing`, apiKey A stored)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "EXISTING_KEY"))
        LifecycleState.shared.beginInitializing()
        let readQueue = seedTestQueueStore()

        // When: dispatch a geofence event with a non-matching API key
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: "DIFFERENT_KEY")
        // Give any (unexpected) async work a beat.
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then: SDK was not re-initialized to B and the event was not enqueued
        XCTAssertEqual(
            SDKConfigStore.shared.current.apiKey, "EXISTING_KEY", "API key should remain unchanged"
        )
        XCTAssertEqual(readQueue().count, 0, "Queue should remain empty")
    }

    func testCreateGeofenceEvent_enqueuesEventWhenAPIKeyMatches() async throws {
        // Given: SDK is initialized with matching API key and items in the queue
        let apiKey = "MATCHING_KEY"
        let readQueue = seedInitialized(apiKey: apiKey, withQueuedItems: true)

        // Capture what the actor sends through the transport.
        let sentRequests = ThreadSafeBox<[KlaviyoRequest]>([])
        environment.klaviyoAPI.send = { request, _ in
            sentRequests.mutate { $0.append(request) }
            return .success(Data())
        }

        // When: dispatch a geofence event with matching API key. The prioritized event is enqueued
        // and forces an immediate flush on the Core RequestQueue actor, which drains the queue.
        GeofenceEventDispatch.dispatch(event: makeGeofenceEvent(), apiKey: apiKey)

        // Then: the event was processed — the forced flush drains the durable queue (async/off-store).
        try await waitUntilQueueEmpty(readQueue)
        assertGeofenceEventSent(sentRequests.value)
        XCTAssertEqual(
            SDKConfigStore.shared.current.apiKey, "MATCHING_KEY", "API key should remain unchanged"
        )
    }

    /// Asserts the sent requests include the geofence event carrying `$geofence_id`.
    private func assertGeofenceEventSent(
        _ sent: [KlaviyoRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let geofenceIds: [String] = sent.compactMap { request in
            guard case let .createEvent(_, payload) = request.endpoint else { return nil }
            let props = payload.data.attributes.properties.value as? [String: Any]
            return props?["$geofence_id"] as? String
        }
        XCTAssertTrue(
            geofenceIds.contains("test-location-id"),
            "the drained batch must send the geofence event with its $geofence_id",
            file: file, line: line
        )
    }

    /// Polls `condition` until true or timeout.
    private func waitFor(
        timeout: TimeInterval = 2.0,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
