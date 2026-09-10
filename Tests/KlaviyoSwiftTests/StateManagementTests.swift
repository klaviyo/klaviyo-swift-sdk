//
//  StateManagementTests.swift
//
//
//  Created by Noah Durell on 12/6/22.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
import Combine
import Foundation
import XCTest

class StateManagementTests: StateManagementTestCase {
    // MARK: - Initialization

    @MainActor
    func testInitialize() async throws {
        let setBadgeExpectation = expectation(description: "BadgeManager.setBadgeCount(0) called on start")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }

        let initialState = KlaviyoState(requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let apiKey = "fake-key"
        // Avoids a warning in xcode despite the result being discardable.
        await store.send(.initialize(apiKey)) {
            $0.apiKey = apiKey
            $0.initalizationState = .initializing
        }

        // The persisted blob is queue-only, so the `completeInitialization` payload
        // loaded from disk carries NO identity (anonymousId nil). The reducer then hydrates the
        // anonymousId from `IdentityStore.shared.current` (minted deterministically to the test
        // uuid), which is what lands in the resulting state.
        let expectedState = KlaviyoState(requestsInFlight: [])
        await store.receive(.completeInitialization(expectedState)) {
            $0.anonymousId = environment.uuid().uuidString
            $0.initalizationState = .initialized
        }

        await store.receive(.start)
        await store.receive(.flushQueue)
        await store.receive(.setPushEnablement(PushEnablement.authorized))
        await fulfillment(of: [setBadgeExpectation], timeout: 1)
    }

    @MainActor
    func testInitializeSubscribesToAppropriatePublishers() async throws {
        let lifecycleExpectation = XCTestExpectation(description: "lifecycle is subscribed")
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        environment.appLifeCycle.lifeCycleEvents = {
            lifecycleSubject.handleEvents(receiveSubscription: { _ in
                lifecycleExpectation.fulfill()
            })
            .eraseToAnyPublisher()
        }
        let initialState = KlaviyoState(requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let apiKey = "fake-key"
        _ = await store.send(.initialize(apiKey))

        lifecycleSubject.send(completion: .finished)

        await fulfillment(of: [lifecycleExpectation], timeout: 1.0)
    }

    /// Regression test: before migration ran here, `.completeInitialization` silently overwrote
    /// decoded legacy identity/pushToken with an empty `IdentityStore`.
    @MainActor
    func testInitializeMigratesLegacyStateIntoCanonicalStores() async throws {
        let fakeEnvironment = InMemoryEnvironment(
            libraryRoot: URL(fileURLWithPath: "/tmp/klaviyo-init-migration-test/library")
        )
        environment = fakeEnvironment.makeEnvironment()
        QueueStore.resetShared()

        let apiKey = "migration-init-key"
        let pushToken = PushTokenData(
            pushToken: "legacy-push", pushEnablement: .authorized, pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
        let legacyQueue = [
            KlaviyoRequest(id: "legacy-a", endpoint: .fetchGeofences(apiKey, latitude: nil, longitude: nil))
        ]
        let fixture = LegacyNestedFixture(
            apiKey: apiKey,
            identity: ProfileData(email: "legacy@user.com", anonymousId: "legacy-anon"),
            pushTokenData: pushToken,
            queue: legacyQueue
        )
        fakeEnvironment[klaviyoStateFile(apiKey: apiKey).path] = try JSONEncoder().encode(fixture)

        // Capture requests reaching the API so we can prove the migrated queue was flushed
        // (the QueueStore is now the sole flush source, so the migrated backlog drains on start).
        let sentRequestIds = ThreadSafeBox<[String]>([])
        environment.klaviyoAPI.send = { request, _ in
            sentRequestIds.mutate { $0.append(request.id) }
            return .success(TEST_RETURN_DATA)
        }

        let initialState = KlaviyoState(requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.initialize(apiKey))
        await store.finish(timeout: 2_000_000_000)

        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, apiKey)
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "legacy-anon")
        XCTAssertEqual(IdentityStore.shared.current.email, "legacy@user.com")
        XCTAssertEqual(IdentityStore.shared.pushToken, pushToken)
        // The migrated queue lands in the Core QueueStore, which is now the sole flush source, and
        // the migrated request drains through it to the API on the post-init flush.
        XCTAssertTrue(
            sentRequestIds.value.contains("legacy-a"),
            "migrated request must flush via the QueueStore"
        )
        XCTAssertEqual(QueueStore.shared.requests, [], "migrated queue drains on flush")
        // The legacy state file is deleted by migration once all stores are verified; no further
        // assertions on file shape are needed (KlaviyoState is no longer Codable).
    }

    /// Seeds the canonical Core stores from a `KlaviyoState` snapshot so that
    /// `RequestEnqueuer` routes to `QueueStore` and reads the correct identity.
    /// Only use where all three stores are seeded from the same `state` value.
    @MainActor
    private func seedCanonicalStores(from state: KlaviyoState) {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: state.apiKey!))
        IdentityStore.shared.update(state.identity)
        IdentityStore.shared.updatePushToken(state.pushTokenData)
    }

    // MARK: - Set Email

    @MainActor
    func testSetEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setEmail("test@blob.com"))

        XCTAssertEqual(
            IdentityStore.shared.current.email, "test@blob.com",
            "setEmail writes the identifier through to the canonical store"
        )
        // A token exists → identifier change re-associates it (token request), folding no pending profile.
        var expectedState = initialState
        expectedState.email = "test@blob.com"
        let expected = expectedState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement
        )
        XCTAssertEqual(readQueue().map(\.endpoint), [expected].map(\.endpoint))
    }

    // MARK: Set Phone Number

    @MainActor
    func testSetPhoneNumber() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setPhoneNumber("+1800555BLOB"))

        XCTAssertEqual(
            IdentityStore.shared.current.phoneNumber, "+1800555BLOB",
            "setPhoneNumber writes the identifier through to the canonical store"
        )
        // A token exists → identifier change re-associates it (token request), folding no pending profile.
        var expectedState = initialState
        expectedState.phoneNumber = "+1800555BLOB"
        let expected = expectedState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement
        )
        XCTAssertEqual(readQueue().map(\.endpoint), [expected].map(\.endpoint))
    }

    // MARK: - Set External Id.

    @MainActor
    func testSetExternalId() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setExternalId("external-blob"))

        XCTAssertEqual(
            IdentityStore.shared.current.externalId, "external-blob",
            "setExternalId writes the identifier through to the canonical store"
        )
        // A token exists → identifier change re-associates it (token request), folding no pending profile.
        var expectedState = initialState
        expectedState.externalId = "external-blob"
        let expected = expectedState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement
        )
        XCTAssertEqual(readQueue().map(\.endpoint), [expected].map(\.endpoint))
    }

    // MARK: - Set Push Token

    @MainActor
    func testSetPushToken() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        initialState.flushing = true // keep the queue observable (no drain)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: initialState.apiKey!))
        IdentityStore.shared.update(initialState.identity)
        IdentityStore.shared.updatePushToken(nil)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setPushToken("blobtoken", .authorized))

        XCTAssertEqual(
            IdentityStore.shared.pushToken?.pushToken, "blobtoken",
            "token persisted to the canonical store"
        )
        let expected = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: "blobtoken", enablement: .authorized
        )
        XCTAssertEqual(readQueue().map(\.endpoint), [expected].map(\.endpoint))
    }

    @MainActor
    func testSetPushTokenEnablementChanged() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData?.pushEnablement = .denied
        initialState.flushing = true // keep the queue observable (no drain)
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setPushToken(initialState.pushTokenData!.pushToken, .authorized))

        XCTAssertEqual(
            IdentityStore.shared.pushToken?.pushEnablement, .authorized,
            "updated enablement persisted to the canonical store"
        )
        var expectedState = initialState
        expectedState.pushTokenData?.pushEnablement = .authorized
        let expected = expectedState.buildTokenRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: .authorized
        )
        XCTAssertEqual(readQueue().map(\.endpoint), [expected].map(\.endpoint))
    }

    @MainActor
    func testSetPushTokenMultipleTimes() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        initialState.flushing = true // keep the queue observable (no drain)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: initialState.apiKey!))
        IdentityStore.shared.update(initialState.identity)
        IdentityStore.shared.updatePushToken(nil)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let pushTokenRequest = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: "blobtoken", enablement: .authorized
        )

        _ = await store.send(.setPushToken("blobtoken", .authorized))
        XCTAssertEqual(readQueue().map(\.endpoint), [pushTokenRequest].map(\.endpoint),
                       "first set enqueues a registration")

        // Second identical send: dedup via IdentityStore — must enqueue nothing.
        _ = await store.send(.setPushToken("blobtoken", .authorized))
        XCTAssertEqual(readQueue().map(\.endpoint), [pushTokenRequest].map(\.endpoint),
                       "second identical set is deduped — queue unchanged")
    }

    // MARK: - Set Push Enablement

    @MainActor
    func testSetPushEnablementPushTokenIsNil() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        // IdentityStore has no token → setPushEnablement is a no-op.
        IdentityStore.shared.updatePushToken(nil)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.setPushEnablement(.authorized))
    }

    @MainActor
    func testSetPushEnablementChanged() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData?.pushEnablement = .denied
        initialState.flushing = true // keep the queue observable (no drain)
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let pushTokenRequest = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: .authorized
        )

        _ = await store.send(.setPushEnablement(.authorized))

        await store.receive(.setPushToken(initialState.pushTokenData!.pushToken, .authorized))
        XCTAssertEqual(readQueue().map(\.endpoint), [pushTokenRequest].map(\.endpoint))
    }

    /// Regression: after a token rotation, `setPushToken` writes the new token to
    /// `IdentityStore` but leaves `state.pushTokenData` stale until the register drains. If
    /// `setPushEnablement` read the stale `state` token it would forward it and clobber the canonical
    /// store back to the old token. It must read the canonical `IdentityStore` token instead.
    @MainActor
    func testSetPushEnablementReadsCanonicalTokenNotStaleState() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        // Simulate the divergence setPushToken(new) creates: state holds the old token, the canonical
        // store already advanced to the rotated one.
        let staleToken = "stale-rotated-away-token"
        let freshToken = "fresh-canonical-token"
        initialState.pushTokenData = PushTokenData(
            pushToken: staleToken, pushEnablement: .authorized, pushBackground: .available,
            deviceData: .init(context: environment.appContextInfo())
        )
        initialState.flushing = true // keep the queue observable (no drain)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: initialState.apiKey!))
        IdentityStore.shared.update(initialState.identity)
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: freshToken, pushEnablement: .authorized, pushBackground: .available,
            deviceData: .init(context: environment.appContextInfo())
        ))
        _ = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setPushEnablement(.denied))

        // Forwards the CANONICAL (fresh) token, not the stale state token.
        await store.receive(.setPushToken(freshToken, .denied))
        // The canonical store keeps the fresh token (not clobbered back to stale), with new enablement.
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, freshToken)
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushEnablement, .denied)
    }

    // MARK: - flush

    @MainActor
    func testFlushQueueLeasesFromQueueStoreIntoInFlight() async throws {
        let apiKey = "fake-key"
        let payload = CreateProfilePayload(data: ProfilePayload(Profile.test, anonymousId: "anon"))
        let request = KlaviyoRequest(endpoint: .createProfile(apiKey, payload))
        resetCanonicalCoreStores()
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        // Seed AFTER resetting the canonical stores — `resetCanonicalCoreStores` clears the
        // shared QueueStore, which would otherwise drop the spy injected here.
        let readQueue = seedTestQueueStore(initial: [request])

        var initialState = KlaviyoState(requestsInFlight: [])
        initialState.apiKey = apiKey
        initialState.initalizationState = .initialized
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        await store.send(.flushQueue) {
            $0.requestsInFlight = [request]
            $0.flushing = true
        }
        XCTAssertEqual(readQueue(), [], "queue is drained into in-flight on flush")
        await store.receive(.sendRequest)
    }

    @MainActor
    func testFlushUninitializedQueueDoesNotFlush() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.flushQueue)
    }

    @MainActor
    func testQueueThatIsFlushingDoesNotFlush() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.flushQueue)
    }

    @MainActor
    func testEmptyQueueDoesNotFlush() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.flushQueue)
    }

    @MainActor
    func testFlushQueueWithMultipleRequests() async throws {
        var count = 0
        // request uuids need to be unique :)
        environment.uuid = {
            count += 1
            switch count {
            case 1:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            case 2:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            default:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            }
        }
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        let readQueue = seedTestQueueStore(initial: [request, request2])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = [request, request2]
        }
        XCTAssertEqual(readQueue(), [], "queue is drained into in-flight on flush")
        await store.receive(.sendRequest)

        await store.receive(.deQueueCompletedResults(request)) {
            $0.flushing = true
            $0.requestsInFlight = [request2]
        }
        await store.receive(.sendRequest)
        await store.receive(.deQueueCompletedResults(request2)) {
            $0.pushTokenData = PushTokenData(pushToken: "blob_token", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.appContextInfo()))
            $0.flushing = false
            $0.requestsInFlight = []
        }
    }

    @MainActor
    func testFlushQueueDuringExponentialBackoff() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryState = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200)
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        seedTestQueueStore(initial: [request, request2])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.retryState = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200 - Int(initialState.flushInterval))
        }
    }

    @MainActor
    func testFlushQueueExponentialBackoffGoesToSize() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryState = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: Int(initialState.flushInterval) - 2)
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        seedTestQueueStore(initial: [request, request2])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.flushQueue) {
            $0.retryState = .retry(23)
            $0.flushing = true
            $0.requestsInFlight = [request, request2]
        }
        await store.receive(.sendRequest)

        // didn't fake uuid since we are not testing this.
        await store.receive(.deQueueCompletedResults(request)) {
            $0.flushing = false
            $0.retryState = .retry(1)
            $0.requestsInFlight = []
        }
    }

    @MainActor
    func testSendRequestWhenNotFlushing() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest)
    }

    // MARK: - send request

    @MainActor
    func testSendRequestWithNoRequestsInFlight() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest) {
            $0.flushing = false
        }
    }

    // MARK: - Network Connectivity Changed

    @MainActor
    func testNetworkConnectivityChanges() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.networkConnectivityChanged(.notReachable)) {
            $0.flushInterval = Double.infinity
        }
        _ = await store.receive(.cancelInFlightRequests) {
            $0.flushing = false
        }
        _ = await store.send(.networkConnectivityChanged(.reachableViaWiFi)) {
            $0.flushing = false
            $0.flushInterval = StateManagementConstants.wifiFlushInterval
        }
        await store.receive(.flushQueue)
        _ = await store.send(.networkConnectivityChanged(.reachableViaWWAN)) {
            $0.flushInterval = StateManagementConstants.cellularFlushInterval
        }
        await store.receive(.flushQueue)
    }

    // MARK: - Stop

    @MainActor
    func testStopWithRequestsInFlight() async throws {
        // This test is a little convoluted but essentially want to make when we stop
        // that we save our state.
        let syncExpectation = expectation(description: "BadgeManager.syncBadgeCount called on stop")
        BadgeManager.syncBadgeCountSpy = { syncExpectation.fulfill() }

        var initialState = INITIALIZED_TEST_STATE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        initialState.requestsInFlight = [request, request2]
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.stop)

        await store.receive(.cancelInFlightRequests) {
            $0.flushing = false
            $0.requestsInFlight = []
        }
        // cancelInFlightRequests restores the in-flight lease to the front of the durable queue.
        XCTAssertEqual(readQueue(), [request, request2])
        await fulfillment(of: [syncExpectation], timeout: 1)
    }

    // MARK: - Test pending profile

    @MainActor
    func testFlushWithPendingProfile() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let profileAttributes: [(Profile.ProfileKey, Any)] = [
            (.city, Profile.test.location!.city!),
            (.region, Profile.test.location!.region!),
            (.address1, Profile.test.location!.address1!),
            (.address2, Profile.test.location!.address2!),
            (.zip, Profile.test.location!.zip!),
            (.country, Profile.test.location!.country!),
            (.latitude, Profile.test.location!.latitude!),
            (.longitude, Profile.test.location!.longitude!),
            (.title, Profile.test.title!),
            (.organization, Profile.test.organization!),
            (.firstName, Profile.test.firstName!),
            (.lastName, Profile.test.lastName!),
            (.image, Profile.test.image!),
            (.custom(customKey: "foo"), 20)
        ]

        var pendingProfile = [Profile.ProfileKey: AnyEncodable]()

        for (key, value) in profileAttributes {
            pendingProfile[key] = AnyEncodable(value)
            _ = await store.send(.setProfileProperty(key, AnyEncodable(value))) {
                $0.pendingProfile = pendingProfile
            }
        }

        // flushQueue enqueues the pending profile/token request into the store, then drains it into
        // the in-memory in-flight lease.
        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.pendingProfile = nil
        }
        XCTAssertEqual(readQueue(), [], "pending profile/token request is drained into in-flight")
        guard let request = store.state.requestsInFlight.first else {
            return XCTFail("expected at least one request in flight after flushQueue")
        }
        switch request.endpoint {
        case let .registerPushToken(_, payload):
            let attrs = payload.data.attributes.profile.data.attributes
            let location = Profile.test.location!
            XCTAssertEqual(attrs.location?.city, location.city)
            XCTAssertEqual(attrs.location?.region, location.region!)
            XCTAssertEqual(attrs.location?.address1, location.address1!)
            XCTAssertEqual(attrs.location?.address2, location.address2!)
            XCTAssertEqual(attrs.location?.zip, location.zip!)
            XCTAssertEqual(attrs.location?.country, location.country!)
            XCTAssertEqual(attrs.location?.latitude, location.latitude!)
            XCTAssertEqual(attrs.location?.longitude, location.longitude!)
            XCTAssertEqual(attrs.title, Profile.test.title)
            XCTAssertEqual(attrs.organization, Profile.test.organization)
            XCTAssertEqual(attrs.firstName, Profile.test.firstName)
            XCTAssertEqual(attrs.lastName, Profile.test.lastName)
            XCTAssertEqual(attrs.image, Profile.test.image)

            if let customProperties = attrs.properties.value as? [String: Any],
               let customFoo = customProperties["foo"] as? Int {
                XCTAssertEqual(customFoo, 20)
            }
        default:
            XCTFail(
                "Wrong endpoint called, expected token update when store's initial state contains token data"
            )
        }

        await store.receive(.sendRequest)
        await store.receive(.deQueueCompletedResults(request)) {
            $0.requestsInFlight = []
            $0.flushing = false
            $0.pendingProfile = nil
            $0.pushTokenData = initialState.pushTokenData
        }
    }

    /// Regression: `flushQueue` with a staged `pendingProfile` calls
    /// `enqueueProfileOrTokenRequest`, which must not leave `state.pushTokenData` nil — otherwise the
    /// write-through `defer` persists nil into `IdentityStore`, wiping the canonical/persisted token
    /// until the in-flight register completes (a crash in that window loses the token on disk).
    @MainActor
    func testFlushWithPendingProfileKeepsCanonicalToken() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        initialState.pendingProfile = [.custom(customKey: "foo"): AnyEncodable("bar")]
        seedCanonicalStores(from: initialState) // seeds IdentityStore.pushToken = the token
        _ = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.flushQueue)

        // The flush must not have wiped the canonical token via the write-through defer.
        XCTAssertEqual(
            IdentityStore.shared.pushToken?.pushToken, initialState.pushTokenData?.pushToken,
            "flush with a pending profile must not wipe the canonical push token"
        )

        // Drain the follow-up effects.
        guard let request = store.state.requestsInFlight.first else {
            return XCTFail("expected a request in flight after flushQueue")
        }
        await store.receive(.sendRequest)
        await store.receive(.deQueueCompletedResults(request))
    }

    // MARK: - Test set profile

    /// Documents the production `enqueueProfile` payload contract: the unified path builds a
    /// `CreateProfilePayload` via `state.profilePayload(from:anonymousId:)` WITHOUT folding any
    /// separately-staged `pendingProfile` property. The staged property stays pending for the next
    /// flush or setter — this matches the legacy post-init behavior (verified in git at 2c8b50da).
    ///
    /// Concretely: a property staged via `setProfileProperty` before a `set(profile:)` call does
    /// NOT appear in that call's `createProfile` payload. It remains staged for the next flush.
    @MainActor
    func testEnqueueProfilePayloadParityWithLegacyBuilder() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let pendingKey = Profile.ProfileKey.custom(customKey: "pending_key")

        // Stage a profile property via the reducer (this is how pendingProfile gets populated).
        _ = await store.send(.setProfileProperty(pendingKey, AnyEncodable("pending_val"))) {
            $0.pendingProfile = [pendingKey: AnyEncodable("pending_val")]
        }

        // Now send a set(profile:) call with Profile.test (which has email, firstName, etc.).
        // Production path: `state.profilePayload(from:anonymousId:)` — NO pendingProfile fold.
        _ = await store.send(.enqueueProfile(Profile.test)) {
            $0.email = Profile.test.email
            $0.phoneNumber = Profile.test.phoneNumber
            $0.externalId = Profile.test.externalId
            // pendingProfile stays staged — enqueueProfile does NOT consume it.
        }

        // Extract the createProfile request from the queue.
        let queued = readQueue()
        guard let profileRequest = queued.first(where: {
            if case .createProfile = $0.endpoint { return true } else { return false }
        }) else {
            return XCTFail("expected a createProfile request in the queue")
        }
        guard case let .createProfile(_, payload) = profileRequest.endpoint else {
            return XCTFail("unexpected endpoint shape")
        }

        let attrs = payload.data.attributes

        // Profile.test's OWN attributes are present in the createProfile payload.
        XCTAssertEqual(attrs.email, Profile.test.email,
                       "profile email must be present in the createProfile payload")
        XCTAssertEqual(attrs.firstName, Profile.test.firstName,
                       "profile firstName must be present in the createProfile payload")

        // The separately-staged pendingProfile property is NOT in this createProfile payload —
        // it remains staged for the next flush (matching legacy enqueueProfile behavior).
        let customProps = attrs.properties.value as? [String: Any]
        XCTAssertNil(
            customProps?["pending_key"],
            "staged-only pendingProfile key must NOT appear in the enqueueProfile createProfile payload"
        )

        // pendingProfile is still staged on state (not consumed by enqueueProfile).
        XCTAssertNotNil(
            store.state.pendingProfile,
            "pendingProfile must remain staged after enqueueProfile (only flush/setter consumes it)"
        )
    }

    @MainActor
    func testSetProfileWithExistingProperties() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        // Seed the canonical stores so the unified `enqueueProfile` path reads the same
        // identity the reducer sees (phoneNumber="555BLOB", push token present).
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Sending a profile with a different email (identifier change on an identified user) →
        // the case resets state (clearing phoneNumber + pushTokenData), then re-associates the
        // token with the new identity via two separate requests: createProfile + registerPushToken.
        _ = await store.send(.enqueueProfile(Profile(email: "foo"))) {
            $0.phoneNumber = nil
            $0.email = "foo"
        }

        // Unified path: two separate requests — profile first, then identity-only token
        // re-association. TokenData was captured pre-reset, so the token itself is preserved.
        // Read anonymousId from the post-send state: the identifier change triggered
        // `state.reset(preserveTokenData: false)` which mints a fresh anonymousId, so the
        // payloads must use the post-reset anonymousId, not the pre-send `initialState` value.
        let apiKey = initialState.apiKey!
        let anonymousId = store.state.anonymousId!
        let profilePayload = CreateProfilePayload(data: ProfilePayload(
            Profile(email: "foo"), email: "foo", anonymousId: anonymousId
        ))
        let tokenPayload = PushTokenPayload(
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement.rawValue,
            background: initialState.pushTokenData!.pushBackground.rawValue,
            profile: ProfilePayload(
                email: "foo", phoneNumber: nil, externalId: nil,
                properties: [:], anonymousId: anonymousId
            )
        )
        let expected: [KlaviyoRequest] = [
            KlaviyoRequest(endpoint: .createProfile(apiKey, profilePayload)),
            KlaviyoRequest(endpoint: .registerPushToken(apiKey, tokenPayload))
        ]
        XCTAssertEqual(readQueue(), expected)
    }

    @MainActor
    func testSetProfileWithAllProfileIdentifiersAndProperties() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        // Seed Core stores so RequestEnqueuer routes to QueueStore (not UnattributedBuffer)
        // and reads the correct identity when building the token re-association payload.
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.enqueueProfile(Profile.test)) {
            $0.email = Profile.test.email
            $0.phoneNumber = Profile.test.phoneNumber
            $0.externalId = Profile.test.externalId
            // No reset — state had no prior identifiers (isIdentified = false),
            // so pushTokenData stays on state.
        }

        // Unified Core path: createProfile (with full structured attributes) + identity-only
        // registerPushToken (no attributes — token re-association only).
        let apiKey = initialState.apiKey!
        let anonymousId = initialState.anonymousId!
        let profilePayload = CreateProfilePayload(data: ProfilePayload(Profile.test, anonymousId: anonymousId))
        let tokenPayload = PushTokenPayload(
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement.rawValue,
            background: initialState.pushTokenData!.pushBackground.rawValue,
            profile: ProfilePayload(
                email: Profile.test.email, phoneNumber: Profile.test.phoneNumber,
                externalId: Profile.test.externalId,
                properties: [:], anonymousId: anonymousId
            )
        )
        let expected: [KlaviyoRequest] = [
            KlaviyoRequest(endpoint: .createProfile(apiKey, profilePayload)),
            KlaviyoRequest(endpoint: .registerPushToken(apiKey, tokenPayload))
        ]
        XCTAssertEqual(readQueue(), expected)
    }

    @MainActor
    func testCreateProfileWithTrailingWhitespaceProperties() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        // Seed Core stores so RequestEnqueuer routes to QueueStore (not UnattributedBuffer)
        // and reads the correct (whitespace-trimmed) identity when building payloads.
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off
        _ = await store.send(
            .enqueueProfile(Profile(email: "foo@blob.com ", phoneNumber: "+19999999999     ",
                                    externalId: "abcdefg    "))
        ) {
            $0.phoneNumber = "+19999999999"
            $0.email = "foo@blob.com"
            $0.externalId = "abcdefg"
            // No reset — state had no prior identifiers (isIdentified = false).
        }

        // Unified Core path: createProfile with trimmed identifiers + identity-only token
        // re-association. IdentityStore is updated with trimmed values before enqueueing.
        let apiKey = initialState.apiKey!
        let anonymousId = store.state.anonymousId!
        let profilePayload = CreateProfilePayload(data: ProfilePayload(
            Profile(email: "foo@blob.com", phoneNumber: "+19999999999", externalId: "abcdefg"),
            anonymousId: anonymousId
        ))
        let tokenPayload = PushTokenPayload(
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement.rawValue,
            background: initialState.pushTokenData!.pushBackground.rawValue,
            profile: ProfilePayload(
                email: "foo@blob.com", phoneNumber: "+19999999999", externalId: "abcdefg",
                properties: [:], anonymousId: anonymousId
            )
        )
        let expected: [KlaviyoRequest] = [
            KlaviyoRequest(endpoint: .createProfile(apiKey, profilePayload)),
            KlaviyoRequest(endpoint: .registerPushToken(apiKey, tokenPayload))
        ]
        XCTAssertEqual(readQueue(), expected)
    }

    // MARK: - Test enqueue event

    /// Payload-parity: the Core path (RequestEnqueuer → RequestFactory.eventPayload) must produce
    /// a structurally identical payload to the legacy reducer path
    /// (updateEventWithIdentifiers + eventRequest) for an identified profile with a push token.
    /// Must pass before the cutover proceeds.
    @MainActor
    func testEnqueueEventPayloadParityWithLegacyBuilder() throws {
        let state = INITIALIZED_TEST_STATE()
        IdentityStore.shared.update(state.identity)
        IdentityStore.shared.updatePushToken(state.pushTokenData)
        let event = Event(name: .customEvent("Test"), properties: ["k": "v"])

        // Legacy build (what post-init did today):
        let enriched = event.updateEventWithIdentifiers(
            email: state.email, phoneNumber: state.phoneNumber,
            externalId: state.externalId, pushToken: state.pushTokenData?.pushToken
        )
        let legacyPayload = RequestFactory.eventPayload(
            identity: PayloadIdentity(
                state.requestIdentity(apiKey: state.apiKey!, anonymousId: state.anonymousId!)),
            event: enriched, pushToken: state.pushTokenData?.pushToken
        )

        // Core build (RequestEnqueuer path):
        let identity = PayloadIdentity(
            anonymousId: state.anonymousId!, email: state.email,
            phoneNumber: state.phoneNumber, externalId: state.externalId
        )
        let corePayload = RequestFactory.eventPayload(
            identity: identity, event: event, pushToken: state.pushTokenData?.pushToken
        )

        XCTAssertEqual(
            legacyPayload,
            corePayload,
            "Core event payload must match the legacy builder"
        )
    }

    /// Verifies payload parity for `._openedPush` — the event type whose `updateEventWithIdentifiers`
    /// push_token branch matters most (it injects the token into event properties).
    @MainActor
    func testOpenedPushEventPayloadParityWithLegacyBuilder() throws {
        let state = INITIALIZED_TEST_STATE()
        IdentityStore.shared.update(state.identity)
        IdentityStore.shared.updatePushToken(state.pushTokenData)
        let pushToken = try XCTUnwrap(state.pushTokenData?.pushToken)
        let event = Event(
            name: ._openedPush,
            properties: ["push_token": pushToken],
            priority: .high
        )

        // Legacy build (what post-init did before the cutover):
        let enriched = event.updateEventWithIdentifiers(
            email: state.email, phoneNumber: state.phoneNumber,
            externalId: state.externalId, pushToken: pushToken
        )
        let legacyPayload = RequestFactory.eventPayload(
            identity: PayloadIdentity(
                state.requestIdentity(apiKey: state.apiKey!, anonymousId: state.anonymousId!)),
            event: enriched, pushToken: pushToken
        )

        // Core build (RequestEnqueuer path):
        let identity = PayloadIdentity(
            anonymousId: state.anonymousId!, email: state.email,
            phoneNumber: state.phoneNumber, externalId: state.externalId
        )
        let corePayload = RequestFactory.eventPayload(
            identity: identity, event: event, pushToken: pushToken
        )

        XCTAssertEqual(
            legacyPayload,
            corePayload,
            "Core _openedPush event payload must match the legacy builder (push_token branch parity)"
        )
    }

    @MainActor
    func testEnqueueEvents() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        // Seed Core stores so RequestEnqueuer routes to QueueStore (not UnattributedBuffer)
        // and reads the correct identity (phone number, push token) when building the payload.
        seedCanonicalStores(from: initialState)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)

        for eventName in Event.EventName.allCases {
            // High-priority events use the package init so that priority flows onto the request.
            let isHighPriority = eventName == ._openedPush
            let event = isHighPriority
                ? Event(
                    name: eventName,
                    properties: ["push_token": initialState.pushTokenData!.pushToken],
                    priority: .high
                )
                : Event(name: eventName, properties: ["push_token": initialState.pushTokenData!.pushToken])
            let expectedPriority: RequestPriority = isHighPriority ? .high : .standard
            // Build the expected request via the Core path so this assertion tracks what
            // RequestEnqueuer actually sends (identity read from IdentityStore above).
            let identity = PayloadIdentity(
                anonymousId: anonymousId, email: initialState.email,
                phoneNumber: initialState.phoneNumber, externalId: initialState.externalId
            )
            let request = KlaviyoRequest(
                endpoint: .createEvent(apiKey, RequestFactory.eventPayload(
                    identity: identity, event: event, pushToken: initialState.pushTokenData?.pushToken
                )),
                priority: expectedPriority
            )
            await store.send(.enqueueEvent(event))
            // High-priority requests are front-inserted inside QueueStore.enqueue.
            if isHighPriority {
                XCTAssertEqual(readQueue().first, request, "high-priority event is front-inserted")
                await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
            } else {
                XCTAssertEqual(readQueue().last, request, "standard event is appended")
            }
        }
    }

    @MainActor
    func testPreInitEventRoutesToUnattributedBuffer() async throws {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset() // no apiKey set → buffer path
        // Exhaustive: any spurious `.flushQueue` or publish-triggered action would fail this test.
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []),
            reducer: KlaviyoReducer()
        )
        // exhaustivity = .on (default) — pre-init enqueueEvent must return .none (no downstream
        // actions). If enrichAndPublishEvent fires or .flushQueue is emitted pre-init, the store
        // will receive an unexpected action and XCTest will report a failure.

        await store.send(.enqueueEvent(.test))
        // No `store.receive(...)` call — verifies that no further actions were produced.

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1, "pre-init event is buffered, not dropped or queued")
    }

    /// Drives the pre-init → drain-on-init flow shared by the buffered event, aggregate-event, and
    /// subscription tests: buffers a request via `bufferPreInit`, initializes the SDK,
    /// then asserts the QueueStore persisted `expectedRequest` and the buffer was trimmed.
    @MainActor
    private func assertPreInitBufferDrainsIntoQueueOnInit(
        bufferPreInit: () -> Void,
        expectedRequest: () throws -> KlaviyoRequest
    ) async throws {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()

        // Buffer a request pre-init (no apiKey known yet).
        bufferPreInit()
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)

        // Record every request the QueueStore ever persists, so the assertion is robust against the
        // post-init flush leasing (then dequeuing) the drained request out of the live backing array.
        let recorded = registerRecordingQueueStore()

        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        await store.send(.initialize(TEST_API_KEY))
        await store.receive(
            .completeInitialization(KlaviyoState(requestsInFlight: [])),
            timeout: TIMEOUT_NANOSECONDS
        )

        // drainBuffer (run inside .initialize) enqueued the buffered request into the QueueStore for
        // this apiKey (it was persisted at some point), and trimmed the buffer.
        let request = try expectedRequest()
        XCTAssertTrue(
            recorded().contains(request),
            "buffered request was drained into the QueueStore at init"
        )
        XCTAssertTrue(
            UnattributedBuffer.shared.drainSnapshot().requests.isEmpty,
            "buffer is trimmed after draining into the queue"
        )
    }

    /// Concrete `TestStore` type produced by ``makePreInitProfileSwitchStore(pushToken:)``.
    private typealias PreInitProfileSwitchStore = TestStore<
        KlaviyoState, KlaviyoAction, KlaviyoState, KlaviyoAction, Void
    >

    /// Resets the canonical stores + buffer, persists an identified user A
    /// ("a@example.com"/"user-A"/"anon-A"), optionally registers a push token, and returns a fresh
    /// non-exhaustive `TestStore` for exercising the pre-init `enqueueProfile` path. Callers keep
    /// their own routing/payload assertions.
    @MainActor
    private func makePreInitProfileSwitchStore(
        pushToken: PushTokenData? = nil
    ) -> PreInitProfileSwitchStore {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()

        IdentityStore.shared.update(ProfileData(
            email: "a@example.com", externalId: "user-A", anonymousId: "anon-A"
        ))
        if let pushToken {
            IdentityStore.shared.updatePushToken(pushToken)
        }

        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off
        return store
    }

    /// Shape B rebind: the profile lives in its own `.profile` buffer entry and the token in a
    /// separate identity-only `.pushToken` entry, both on the new (post-reset) identity. Asserts that
    /// pair, then drains at init and asserts exactly one createProfile and one registerPushToken.
    @MainActor
    private func assertPreInitRebindProducesSeparateProfileAndToken(
        _ store: PreInitProfileSwitchStore, email: String, token: String, oldAnon: String
    ) async {
        let snap = UnattributedBuffer.shared.snapshot()
        let profiles: [CreateProfilePayload] = snap.compactMap {
            if case let .profile(payload) = $0 { return payload }
            return nil
        }
        let tokens: [PushTokenPayload] = snap.compactMap {
            if case let .pushToken(payload) = $0 { return payload }
            return nil
        }
        XCTAssertEqual(profiles.count, 1, "profile kept in its own entry, safe from token coalescing")
        XCTAssertEqual(tokens.count, 1, "one identity-only token registration")
        XCTAssertEqual(profiles.first?.data.attributes.email, email)
        XCTAssertNotEqual(profiles.first?.data.attributes.anonymousId, oldAnon)
        XCTAssertEqual(tokens.first?.data.attributes.token, token)
        XCTAssertEqual(tokens.first?.data.attributes.profile.data.attributes.email, email)

        let recorded = registerRecordingQueueStore()
        await store.send(.initialize(TEST_API_KEY))
        await store.receive(
            .completeInitialization(KlaviyoState(requestsInFlight: [])), timeout: TIMEOUT_NANOSECONDS
        )
        let createsToNewIdentity = recorded().filter {
            if case let .createProfile(_, payload) = $0.endpoint {
                return payload.data.attributes.email == email
            }
            return false
        }
        let registers = recorded().filter {
            if case .registerPushToken = $0.endpoint { return true } else { return false }
        }
        XCTAssertFalse(createsToNewIdentity.isEmpty, "profile synced to the new identity")
        XCTAssertEqual(registers.count, 1, "token registered once, to the new identity")
        XCTAssertTrue(UnattributedBuffer.shared.drainSnapshot().requests.isEmpty)
    }

    @MainActor
    func testPreInitProfileSwitchRebindsTokenToNewIdentity() async throws {
        // A previously-identified user A with a registered push token; pre-init switch to user B.
        let store = makePreInitProfileSwitchStore(pushToken: PushTokenData(
            pushToken: "tok-1", pushEnablement: .authorized,
            pushBackground: .available, deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))

        await store.send(.enqueueProfile(Profile(email: "b@example.com", externalId: "user-B")))

        await assertPreInitRebindProducesSeparateProfileAndToken(
            store, email: "b@example.com", token: "tok-1", oldAnon: "anon-A"
        )
    }

    @MainActor
    func testPreInitTokenSetBeforeProfileSwitchRebindsToNewIdentity() async throws {
        // Token set pre-init (buffered, not yet in IdentityStore), then a pre-init profile switch:
        // the switch must rebind the token to the new identity, not strand it on the old one.
        let store = makePreInitProfileSwitchStore() // user A, no token pre-seeded in IdentityStore

        await store.send(.setPushToken("tok-1", .authorized))
        await store.send(.enqueueProfile(Profile(email: "b@example.com", externalId: "user-B")))

        // The stale standalone token registration coalesces away; the profile and the rebound
        // (identity-only) token land as separate entries for user B.
        await assertPreInitRebindProducesSeparateProfileAndToken(
            store, email: "b@example.com", token: "tok-1", oldAnon: "anon-A"
        )
    }

    @MainActor
    func testPreInitProfileAttributesSurviveLaterTokenRegistration() async throws {
        // A profile with structured attributes is set pre-init, THEN a push-token registration
        // arrives (a manual setPushToken here; an automatic APNs callback forwards to the same path
        // and commonly fires async, after set(profile:)). The token registration must NOT clobber
        // the profile's attributes — they live in a separate `.profile` entry, immune to push-token
        // coalescing.
        let store = makePreInitProfileSwitchStore(pushToken: PushTokenData(
            pushToken: "tok-1", pushEnablement: .authorized,
            pushBackground: .available, deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))

        await store.send(.enqueueProfile(
            Profile(email: "b@example.com", externalId: "user-B", firstName: "Bob")
        ))
        await store.send(.setPushToken("tok-1", .authorized))

        // The profile's structured attributes are preserved in the `.profile` entry.
        let profile: CreateProfilePayload? = UnattributedBuffer.shared.snapshot().compactMap {
            if case let .profile(payload) = $0 { return payload }
            return nil
        }.first
        XCTAssertEqual(
            try XCTUnwrap(profile).data.attributes.firstName, "Bob",
            "profile attributes must survive a later token registration"
        )

        await assertPreInitRebindProducesSeparateProfileAndToken(
            store, email: "b@example.com", token: "tok-1", oldAnon: "anon-A"
        )
    }

    @MainActor
    func testPreInitProfileWithoutTokenStillBuffersBareProfile() async throws {
        // No push token registered.
        let store = makePreInitProfileSwitchStore()
        await store.send(.enqueueProfile(Profile(email: "b@example.com", externalId: "user-B")))

        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case let .profile(payload) = snap[0] else {
            return XCTFail("expected bare .profile in buffer when no token is registered")
        }
        XCTAssertEqual(payload.data.attributes.email, "b@example.com")
    }

    @MainActor
    func testPreInitBufferedEventDrainsIntoQueueOnInit() async throws {
        try await assertPreInitBufferDrainsIntoQueueOnInit(
            bufferPreInit: { RequestEnqueuer.enqueueEvent(.test) },
            expectedRequest: {
                try KlaviyoRequest(
                    endpoint: .createEvent(
                        TEST_API_KEY,
                        CreateEventPayload(
                            data: CreateEventPayload.Event(
                                name: Event.test.metric.name.value,
                                properties: Event.test.properties,
                                anonymousId: environment.uuid().uuidString,
                                time: Event.test.time
                            )
                        )
                    )
                )
            }
        )
    }

    // MARK: - Test enqueue aggregate event

    @MainActor
    func testEnqueueAggregateEvent() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        // Seed SDKConfigStore so RequestEnqueuer routes to QueueStore (not UnattributedBuffer).
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: initialState.apiKey!))
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let data = Data()
        await store.send(.enqueueAggregateEvent(data))
        let request = try KlaviyoRequest(
            endpoint: .aggregateEvent(XCTUnwrap(initialState.apiKey), AggregateEventPayload(data))
        )
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testPreInitAggregateEventDrainsIntoQueueOnInit() async throws {
        let data = Data()
        try await assertPreInitBufferDrainsIntoQueueOnInit(
            bufferPreInit: { RequestEnqueuer.enqueueAggregateEvent(data) },
            expectedRequest: {
                try KlaviyoRequest(
                    endpoint: .aggregateEvent(TEST_API_KEY, AggregateEventPayload(data))
                )
            }
        )
    }

    @MainActor
    func testPrioritizedEventsAreInsertedAtFrontOfQueue() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false

        // Seed Core stores so RequestEnqueuer routes to QueueStore (not UnattributedBuffer)
        // and reads the correct identity (push token) when building the geofence event payload.
        seedCanonicalStores(from: initialState)

        // Add some existing requests to the queue
        let existingRequest1 = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let existingRequest2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "token1", enablement: .authorized)
        seedTestQueueStore(initial: [existingRequest1, existingRequest2])

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Test geofence event is inserted at front.
        // Geofence events set priority: .high at the producer site; mirror that here.
        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"],
            priority: .high
        )

        let geofenceRequest = try KlaviyoRequest(
            endpoint: .createEvent(
                XCTUnwrap(store.state.apiKey),
                CreateEventPayload(
                    data: CreateEventPayload.Event(
                        name: geofenceEvent.metric.name.value,
                        properties: geofenceEvent.properties,
                        phoneNumber: store.state.phoneNumber,
                        anonymousId: initialState.anonymousId!,
                        time: geofenceEvent.time,
                        pushToken: store.state.pushTokenData?.pushToken
                    )
                )
            ),
            priority: .high
        )
        await store.send(.enqueueEvent(geofenceEvent))

        var actualGeofenceRequest: KlaviyoRequest?
        await store.receive(.flushQueue) {
            $0.flushing = true
            // Geofence event is prioritized → front-inserted by QueueStore, then drained first.
            XCTAssertEqual($0.requestsInFlight.count, 3, "Should have 3 requests in flight")
            guard $0.requestsInFlight.count == 3 else {
                XCTFail("Expected 3 requests in flight, got \($0.requestsInFlight.count) — skipping index assertions")
                return
            }
            actualGeofenceRequest = $0.requestsInFlight[0]
            if case let .createEvent(_, payload) = actualGeofenceRequest!.endpoint {
                XCTAssertEqual(
                    payload.data.attributes.metric.data.attributes.name,
                    "$geofence_enter",
                    "First request in flight should be geofence event"
                )
            } else {
                XCTFail("First request in flight should be geofence event")
            }
            XCTAssertEqual(
                $0.requestsInFlight[0].id, geofenceRequest.id,
                "First request should be the geofence event"
            )
            XCTAssertEqual($0.requestsInFlight[1].id, existingRequest1.id, "Second request should be existing request 1")
            XCTAssertEqual($0.requestsInFlight[2].id, existingRequest2.id, "Third request should be existing request 2")
        }
        await store.receive(.sendRequest)
        await store.receive(.deQueueCompletedResults(actualGeofenceRequest!)) {
            $0.requestsInFlight.removeAll { $0.id == actualGeofenceRequest!.id }
            $0.retryState = .retry(1)
            $0.flushing = false
        }
    }

    // MARK: - enqueueSubscription

    /// Builds the `KlaviyoRequest` a subscription enqueue is expected to produce.
    private func expectedSubscriptionRequest(
        apiKey: String,
        listId: String = "list-123",
        profile: ProfilePayload
    ) -> KlaviyoRequest {
        KlaviyoRequest(
            endpoint: .createSubscription(apiKey, CreateSubscriptionPayload(listId: listId, profile: profile))
        )
    }

    @MainActor
    func testEnqueueSubscription() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(initialState.identity)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(email: "test@example.com", anonymousId: anonymousId)
        )
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        await store.send(.enqueueSubscription(subscription))
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testEnqueueSubscriptionWithChannels() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        initialState.phoneNumber = "+15005550006"

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(initialState.identity)
        let subscription = Subscription(
            listId: "list-123",
            channels: .init(email: .marketing, sms: .marketing)
        )
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(
                email: "test@example.com",
                phoneNumber: "+15005550006",
                subscriptions: SubscriptionChannels(
                    email: EmailConsent(marketing: .subscribed),
                    sms: MarketingTransactionalConsent(marketing: .subscribed)
                ),
                anonymousId: anonymousId
            )
        )
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        await store.send(.enqueueSubscription(subscription))
        XCTAssertEqual(readQueue(), [request])
    }

    /// Overrides `environment.emitDeveloperWarning` with an expectation that fulfills only when a
    /// warning containing `fragment` fires, pinning down which guard in enqueueSubscription was taken.
    @MainActor
    private func expectSubscriptionWarning(
        containing fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "developer warning containing: \(fragment)")
        environment.emitDeveloperWarning = { message in
            XCTAssertTrue(
                message.contains(fragment),
                "expected warning containing \"\(fragment)\" but got \"\(message)\"",
                file: file,
                line: line
            )
            expectation.fulfill()
        }
        return expectation
    }

    @MainActor
    func testEnqueueSubscriptionUninitializedBuffers() async throws {
        // Pre-init: a subscribe carrying an identifier buffers its apiKey-free payload in the durable
        // UnattributedBuffer (drains into the QueueStore at initialize()) instead of the earlier
        // warn + drop. Mirrors the initialized path against the canonical persisted identity.
        IdentityStore.shared.update(ProfileData(email: "test@example.com", anonymousId: "anon-1"))
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        await store.send(.enqueueSubscription(Subscription.allAvailableMarketing(listId: "list-123")))

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1, "pre-init subscription is buffered, not dropped")
        guard case let .subscription(payload) = buffered.first else {
            return XCTFail("expected a buffered .subscription")
        }
        XCTAssertEqual(payload.data.relationships.list.data.id, "list-123")
        XCTAssertEqual(
            payload.data.attributes.profile.data.attributes.email, "test@example.com",
            "the persisted identity is folded into the buffered subscription payload"
        )
    }

    @MainActor
    func testPreInitSubscriptionDrainsIntoQueueOnInit() async throws {
        // Restores the earlier "pending subscription replays on init" coverage: a subscribe
        // buffered before initialize() drains into the QueueStore when the SDK initializes.
        let payload = CreateSubscriptionPayload(
            listId: "list-123",
            profile: ProfilePayload(email: "test@example.com", anonymousId: "anon-1")
        )
        try await assertPreInitBufferDrainsIntoQueueOnInit(
            bufferPreInit: { RequestEnqueuer.enqueueSubscription(payload: payload) },
            expectedRequest: {
                KlaviyoRequest(endpoint: .createSubscription(TEST_API_KEY, payload))
            }
        )
    }

    @MainActor
    func testEnqueueSubscriptionMissingIdentifiersDoesNotEnqueue() async throws {
        // Explicitly seed IdentityStore with the test identity (anonymousId only, no email/phone/externalId).
        // `state.identity = IdentityStore.shared.current` in the reducer reads it back unchanged,
        // so `buildSubscriptionPayload` sees no identifiers, warns, and returns nil → no enqueue.
        let expectation = expectSubscriptionWarning(containing: "at least one identifier")
        let initialState = INITIALIZED_TEST_STATE()
        try SDKConfigStore.shared.update(KlaviyoConfig(apiKey: XCTUnwrap(initialState.apiKey)))
        // Seed IdentityStore to match initialState (anonymousId only) so the reducer's identity
        // seed is a no-op in exhaustive mode and the no-identifiers guard fires as intended.
        IdentityStore.shared.update(initialState.identity)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription.allAvailableMarketing(listId: "list-123")))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(readQueue().isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionAllAvailableMarketingWithPhoneOnly() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "+15005550006"

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(initialState.identity)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(phoneNumber: "+15005550006", anonymousId: anonymousId)
        )
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        await store.send(.enqueueSubscription(subscription))
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testEnqueueSubscriptionEmptyChannelsDoesNotEnqueue() async throws {
        // Empty channels (`SubscriptionChannels()`) fails the `mappedChannels` guard before any
        // identifier check — `buildSubscriptionPayload` warns "none were enabled" and returns nil.
        // Seed IdentityStore to match state so `state.identity = IdentityStore.shared.current`
        // is a no-op (avoids a spurious TCA state-mutation in exhaustive mode).
        let expectation = expectSubscriptionWarning(containing: "none were enabled")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        try SDKConfigStore.shared.update(KlaviyoConfig(apiKey: XCTUnwrap(initialState.apiKey)))
        IdentityStore.shared.update(initialState.identity)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init())))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(readQueue().isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionEmailChannelWithoutEmailDoesNotEnqueue() async throws {
        // An email-channel subscription without an email set → `buildSubscriptionPayload` warns
        // "requires an email" and returns nil → no enqueue. Seed IdentityStore to match state
        // (phone only, no email) so the identity seed is a no-op in exhaustive mode.
        let expectation = expectSubscriptionWarning(containing: "requires an email")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "+15005550006"
        try SDKConfigStore.shared.update(KlaviyoConfig(apiKey: XCTUnwrap(initialState.apiKey)))
        IdentityStore.shared.update(initialState.identity)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init(email: .marketing))))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(readQueue().isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionPhoneChannelWithoutPhoneDoesNotEnqueue() async throws {
        // An SMS-channel subscription without a phone set → `buildSubscriptionPayload` warns
        // "requires a phone number" and returns nil → no enqueue. Seed IdentityStore to match
        // state (email only, no phone) so the identity seed is a no-op in exhaustive mode.
        let expectation = expectSubscriptionWarning(containing: "requires a phone number")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        try SDKConfigStore.shared.update(KlaviyoConfig(apiKey: XCTUnwrap(initialState.apiKey)))
        IdentityStore.shared.update(initialState.identity)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init(sms: .marketing))))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(readQueue().isEmpty)
    }

    // MARK: - Request priority

    /// Concrete `TestStore` type produced by ``makePriorityTestStore()``.
    private typealias PriorityTestStore = TestStore<
        KlaviyoState, KlaviyoAction, KlaviyoState, KlaviyoAction, Void
    >

    /// Named result of ``makePriorityTestStore()`` — avoids positional tuple destructuring.
    private struct PriorityTestScaffold {
        let store: PriorityTestStore
        let seededRequest: KlaviyoRequest
        let readQueue: () -> [KlaviyoRequest]
    }

    /// Builds a non-flushing store seeded with a single standard-priority queued request,
    /// so front-insertion (high priority) vs. append (standard) is observable. Seeds the Core
    /// stores so RequestEnqueuer routes to QueueStore and reads the correct identity.
    /// Returns the store together with the seeded request for identity assertions.
    @MainActor
    private func makePriorityTestStore() -> PriorityTestScaffold {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        // Seed Core stores so RequestEnqueuer routes to QueueStore (not UnattributedBuffer)
        // and reads the correct identity when building event payloads.
        seedCanonicalStores(from: initialState)
        let existingRequest = initialState.buildProfileRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!
        )
        let readQueue = seedTestQueueStore(initial: [existingRequest])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        return PriorityTestScaffold(store: store, seededRequest: existingRequest, readQueue: readQueue)
    }

    @MainActor
    func testOpenedPushEventProducesHighPriorityRequestAtQueueFront() async throws {
        let scaffold = makePriorityTestStore()
        // Assert only the priority/front-insert/flush contract; the full network flush
        // chain is exercised by testPrioritizedEventsAreInsertedAtFrontOfQueue.
        scaffold.store.exhaustivity = .off

        let event = Event(name: ._openedPush, properties: ["foo": "bar"], priority: .high)
        await scaffold.store.send(.enqueueEvent(event))

        // The high-priority event is front-inserted into the QueueStore and immediately flushed,
        // leasing the queue into `requestsInFlight` with the opened-push request at the front.
        await scaffold.store.receive(.flushQueue)
        XCTAssertEqual(
            scaffold.store.state.requestsInFlight.count, 2,
            "Existing + new request should be in flight"
        )
        let front = try XCTUnwrap(scaffold.store.state.requestsInFlight.first)
        XCTAssertEqual(
            front.priority,
            .high,
            "Opened-push request must carry .high priority and be inserted at the front"
        )
    }

    @MainActor
    func testGeofenceEventProducesHighPriorityRequestAtQueueFront() async throws {
        let scaffold = makePriorityTestStore()
        // Assert only the priority/front-insert/flush contract; the full network flush
        // chain is exercised by testPrioritizedEventsAreInsertedAtFrontOfQueue.
        scaffold.store.exhaustivity = .off

        let event = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "region-123"],
            priority: .high
        )
        await scaffold.store.send(.enqueueEvent(event))

        // The high-priority event is front-inserted into the QueueStore and immediately flushed,
        // leasing the queue into `requestsInFlight` with the geofence request at the front.
        await scaffold.store.receive(.flushQueue)
        XCTAssertEqual(
            scaffold.store.state.requestsInFlight.count, 2,
            "Existing + new request should be in flight"
        )
        let front = try XCTUnwrap(scaffold.store.state.requestsInFlight.first)
        XCTAssertEqual(
            front.priority,
            .high,
            "Geofence request must carry .high priority and be inserted at the front"
        )
    }

    @MainActor
    func testStandardEventProducesStandardPriorityRequestAppendedToQueue() async throws {
        let scaffold = makePriorityTestStore()
        let store = scaffold.store
        let existingRequest = scaffold.seededRequest
        let readQueue = scaffold.readQueue
        store.exhaustivity = .off

        let event = Event(name: .openedAppMetric)
        let request = try KlaviyoRequest(
            endpoint: .createEvent(
                XCTUnwrap(store.state.apiKey),
                CreateEventPayload(
                    data: CreateEventPayload.Event(
                        name: Event.EventName.openedAppMetric.value,
                        properties: event.properties,
                        phoneNumber: store.state.phoneNumber,
                        anonymousId: store.state.anonymousId!,
                        time: event.time,
                        pushToken: store.state.pushTokenData?.pushToken
                    )
                )
            ),
            priority: .standard
        )
        await store.send(.enqueueEvent(event))
        // Standard request is appended; existing request stays at front
        XCTAssertEqual(readQueue()[0].id, existingRequest.id, "Existing request should remain at queue[0]")
        XCTAssertEqual(readQueue().last?.priority, .standard, "Standard event produces .standard request")
        XCTAssertEqual(readQueue().last?.id, request.id, "Standard request is appended at the tail")
        // No flushQueue emitted for standard-priority events
    }

    // MARK: - Core store write-through

    @MainActor
    func testInitializeWritesApiKeyThroughToConfigStore() async throws {
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.initialize("write-through-key"))

        XCTAssertEqual(
            SDKConfigStore.shared.current.apiKey, "write-through-key",
            "initialize must write the confirmed apiKey through to the canonical config store"
        )
    }

    @MainActor
    func testSetEmailWritesIdentityThroughToIdentityStore() async throws {
        let store = TestStore(initialState: INITIALIZED_TEST_STATE(), reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setEmail("writethrough@klaviyo.com"))

        XCTAssertEqual(
            IdentityStore.shared.current.email, "writethrough@klaviyo.com",
            "setEmail must write the mutated identity through to the canonical identity store"
        )
    }

    @MainActor
    func testResetProfileMintsFreshAnonymousIdThroughIdentityStore() async throws {
        IdentityStore.shared.update(ProfileData(email: "old@klaviyo.com", anonymousId: "anon-before"))
        var seeded = INITIALIZED_TEST_STATE()
        seeded.email = "old@klaviyo.com"
        seeded.anonymousId = "anon-before"
        // Seed Core stores so RequestEnqueuer routes to QueueStore (not UnattributedBuffer)
        // and reads the correct identity when re-registering the token after reset.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: seeded.apiKey!))
        IdentityStore.shared.updatePushToken(seeded.pushTokenData)
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: seeded, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.resetProfile)

        XCTAssertNil(IdentityStore.shared.current.email, "reset clears identity through the store")
        XCTAssertNotNil(IdentityStore.shared.current.anonymousId)
        XCTAssertNotEqual(
            IdentityStore.shared.current.anonymousId, "anon-before",
            "reset of an identified profile mints a fresh anonymousId via IdentityStore"
        )

        // Token must be re-registered under the new anonymous identity via the ungated
        // RequestEnqueuer (not the apiKey-gated state.enqueueRequest).
        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "reset enqueues exactly one token re-register")
        guard case let .registerPushToken(apiKey, payload) = queued.first?.endpoint else {
            XCTFail("expected a registerPushToken request in the queue after reset")
            return
        }
        XCTAssertEqual(apiKey, seeded.apiKey!, "token re-register uses the current apiKey")
        XCTAssertEqual(payload.data.attributes.token, seeded.pushTokenData!.pushToken,
                       "preserved push token is re-registered")
        XCTAssertEqual(
            payload.data.attributes.profile.data.attributes.anonymousId,
            IdentityStore.shared.current.anonymousId,
            "token re-register uses the post-reset (fresh) anonymousId"
        )
    }

    // MARK: - Enqueue-during-initializing (defensive race test)

    /// Regression/defensive: a request-generating action dispatched while the reducer is
    /// `.initializing` (after apiKey is committed) must land in the resolved QueueStore and must
    /// NOT be stranded in the UnattributedBuffer.
    ///
    /// This verifies that the `.initializing` state does not create a "black hole" window where
    /// events are lost — the buffer is fully drained before the reducer reaches `.initialized`.
    @MainActor
    func testEnqueueDuringInitializingRoutesToQueueStoreNotBuffer() async throws {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()

        // Set up a recording spy for the apiKey so we can observe every persisted request,
        // even ones that are flushed out of the live array immediately after initialization.
        let recorded = registerRecordingQueueStore()

        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        // `.initialize` sets `state.apiKey` and the write-through `defer` commits it to
        // SDKConfigStore synchronously, all within this `send` — before the returned `.run`
        // (migrate + drainBuffer) runs and before any later action can be processed.
        await store.send(.initialize(TEST_API_KEY))

        // With the apiKey now committed, an enqueue during `.initializing` routes straight to
        // the resolved QueueStore: the buffer path (taken only when the apiKey is absent) is
        // already closed. The request is NOT parked in UnattributedBuffer awaiting a drain.
        RequestEnqueuer.enqueueEvent(.test)

        let expectedRequest = try KlaviyoRequest(
            endpoint: .createEvent(
                TEST_API_KEY,
                CreateEventPayload(
                    data: CreateEventPayload.Event(
                        name: Event.test.metric.name.value,
                        properties: Event.test.properties,
                        anonymousId: environment.uuid().uuidString,
                        time: Event.test.time
                    )
                )
            )
        )

        // Mechanism proof: the event is in QueueStore immediately — before
        // `.completeInitialization` — and nothing is stranded in the buffer.
        XCTAssertTrue(
            recorded().contains(expectedRequest),
            "event enqueued during .initializing must route directly to QueueStore"
        )
        XCTAssertTrue(
            UnattributedBuffer.shared.drainSnapshot().requests.isEmpty,
            "event during .initializing must not be parked in UnattributedBuffer"
        )

        // Let the initialization effect settle so the store finishes cleanly.
        await store.receive(
            .completeInitialization(KlaviyoState(requestsInFlight: [])),
            timeout: TIMEOUT_NANOSECONDS
        )
    }

    // MARK: - Empty / unchanged setter short-circuit (regression gate)

    private enum IdentifierField { case email, phone, externalId }

    /// Sends the setter for `field` with `value` and asserts nothing is enqueued.
    /// `seedStored == true` seeds `value` as the canonical identifier first (exercises the
    /// "unchanged" guard); `false` leaves it unset (exercises the "empty string" short-circuit).
    @MainActor
    private func assertSetterEnqueuesNothing(
        field: IdentifierField,
        value: String,
        seedStored: Bool
    ) async throws {
        let initialState = INITIALIZED_TEST_STATE()
        if seedStored {
            SDKConfigStore.shared.update(KlaviyoConfig(apiKey: initialState.apiKey!))
            var identity = ProfileData(anonymousId: initialState.anonymousId)
            switch field {
            case .email: identity.email = value
            case .phone: identity.phoneNumber = value
            case .externalId: identity.externalId = value
            }
            IdentityStore.shared.update(identity)
            IdentityStore.shared.updatePushToken(initialState.pushTokenData)
        } else {
            seedCanonicalStores(from: initialState)
        }
        let readQueue = seedTestQueueStore()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let action: KlaviyoAction
        switch field {
        case .email: action = .setEmail(value)
        case .phone: action = .setPhoneNumber(value)
        case .externalId: action = .setExternalId(value)
        }
        _ = await store.send(action)

        XCTAssertTrue(readQueue().isEmpty, "\(action) must not enqueue any request")
    }

    /// The singular identifier setters must enqueue nothing when handed an empty string or the value
    /// already stored — the `isNotEmptyOrSame` guard the old per-setter paths applied. Covers all
    /// three fields × {empty, unchanged}.
    @MainActor
    func testIdentifierSettersShortCircuitOnEmptyOrUnchanged() async throws {
        // Empty string → short-circuits before any comparison, regardless of the stored value.
        try await assertSetterEnqueuesNothing(field: .email, value: "", seedStored: false)
        try await assertSetterEnqueuesNothing(field: .phone, value: "", seedStored: false)
        try await assertSetterEnqueuesNothing(field: .externalId, value: "", seedStored: false)
        // Unchanged value → guard compares against the stored identifier and short-circuits.
        try await assertSetterEnqueuesNothing(field: .email, value: "same@example.com", seedStored: true)
        try await assertSetterEnqueuesNothing(field: .phone, value: "+18005551234", seedStored: true)
        try await assertSetterEnqueuesNothing(field: .externalId, value: "user-42", seedStored: true)
    }

    // MARK: - resetProfile preserves canonical push token in IdentityStore (regression gate)

    /// `resetProfile` must NOT transiently clear `IdentityStore.pushToken`. The base
    /// `state.reset(preserveTokenData: false)` sets `state.pushTokenData = nil`, which would cause
    /// the write-through `defer` to call `IdentityStore.shared.updatePushToken(nil)`. The fix
    /// restores `state.pushTokenData` to the captured token before returning so the defer is a no-op.
    @MainActor
    func testResetProfilePreservesCanonicalPushToken() async throws {
        var seeded = INITIALIZED_TEST_STATE()
        seeded.email = "old@klaviyo.com"
        seeded.anonymousId = "anon-before"
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: seeded.apiKey!))
        IdentityStore.shared.update(ProfileData(email: "old@klaviyo.com", anonymousId: "anon-before"))
        IdentityStore.shared.updatePushToken(seeded.pushTokenData)
        seedTestQueueStore()
        let store = TestStore(initialState: seeded, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.resetProfile)

        XCTAssertNotNil(
            IdentityStore.shared.pushToken,
            "resetProfile must not clear the canonical push token in IdentityStore"
        )
        XCTAssertEqual(
            IdentityStore.shared.pushToken?.pushToken, seeded.pushTokenData?.pushToken,
            "the preserved token must match the pre-reset token"
        )
    }

    // MARK: - Pre-init identifier change with stored token (regression gate)

    /// When an app calls `setEmail` before `initialize()` and a push token is already stored in
    /// `IdentityStore`, the token branch inside `applyIdentifierChange` must be gated on
    /// `apiKey`-present. Without the gate, the branch builds a token request with an empty apiKey,
    /// `enqueueRequest` drops it (nil-apiKey guard), and the profile update is **silently lost**.
    /// The expected behavior — matching the legacy `setPreInitIdentifier` — is to fall through to
    /// the profile branch and buffer a `.profile` entry in `UnattributedBuffer`.
    @MainActor
    func testSetEmailPreInitWithStoredTokenBuffersProfile() async throws {
        // Arrange: uninitialized state (no apiKey), identity with anonymousId, and a stored token.
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        IdentityStore.shared.update(ProfileData(
            email: "old@example.com", externalId: "user-A", anonymousId: "anon-A"
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "tok-preInit",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))

        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        // Act: change email while still pre-init (no apiKey set).
        await store.send(.setEmail("new@example.com"))

        // Assert: a `.profile` entry carrying the new email must be in the buffer.
        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let profiles: [CreateProfilePayload] = snap.compactMap {
            if case let .profile(payload) = $0 { return payload }
            return nil
        }
        XCTAssertEqual(profiles.count, 1,
                       "pre-init setEmail with a stored token must buffer a .profile, not drop silently")
        XCTAssertEqual(profiles.first?.data.attributes.email, "new@example.com",
                       "buffered profile must carry the updated email")
    }

    /// Warm-start variant: `SDKConfigStore` holds a persisted apiKey (from a prior launch) but
    /// `.initialize` has not run this launch, so `state.apiKey` is still nil. The token branch must
    /// gate on `state.apiKey` (which `enqueueRequest` uses), not the persisted `SDKConfigStore`
    /// apiKey — otherwise the request is built and silently dropped by the nil-`state.apiKey` guard.
    /// With the gate, it falls through to `RequestEnqueuer.enqueueProfile`, which — since
    /// `SDKConfigStore` has the apiKey — routes the profile to the `QueueStore` (not dropped).
    /// Regression gate for the warm-start drop.
    @MainActor
    func testSetEmailWarmStartWithStoredTokenEnqueuesProfileToQueue() async throws {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // Persisted apiKey from a prior launch: present in SDKConfigStore but NOT yet on state.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "persisted-key"))
        IdentityStore.shared.update(ProfileData(
            email: "old@example.com", externalId: "user-A", anonymousId: "anon-A"
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "tok-warmStart",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        let readQueue = seedTestQueueStore()

        // Uninitialized state: state.apiKey is nil even though SDKConfigStore has one.
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        await store.send(.setEmail("new@example.com"))

        // Not dropped: a createProfile carrying the new email lands in the QueueStore.
        let profiles: [CreateProfilePayload] = readQueue().compactMap {
            if case let .createProfile(_, payload) = $0.endpoint { return payload }
            return nil
        }
        XCTAssertEqual(profiles.count, 1,
                       "warm-start setEmail (SDKConfigStore apiKey set, state.apiKey nil) must enqueue a profile, not drop")
        XCTAssertEqual(profiles.first?.data.attributes.email, "new@example.com")
    }
}
