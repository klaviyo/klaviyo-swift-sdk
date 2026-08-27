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

class StateManagementTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        BadgeManager.resetToProduction()
    }

    @MainActor
    override func tearDown() async throws {
        BadgeManager.resetToProduction()
    }

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
        QueueStore.resetRegistry()

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
        XCTAssertEqual(QueueStore.store(for: apiKey).requests, [], "migrated queue drains on flush")
        // The legacy state file is deleted by migration once all stores are verified; no further
        // assertions on file shape are needed (KlaviyoState is no longer Codable).
    }

    // MARK: - Set Email

    @MainActor
    func testSetEmail() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setEmail("test@blob.com")) {
            $0.email = "test@blob.com"
            $0.pushTokenData = nil
        }
        var expectedState = initialState
        expectedState.email = "test@blob.com"
        let request = expectedState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement
        )
        XCTAssertEqual(readQueue(), [request])
    }

    // MARK: Set Phone Number

    @MainActor
    func testSetPhoneNumber() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setPhoneNumber("+1800555BLOB")) {
            $0.phoneNumber = "+1800555BLOB"
            $0.pushTokenData = nil
        }
        var expectedState = initialState
        expectedState.phoneNumber = "+1800555BLOB"
        let request = expectedState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement
        )
        XCTAssertEqual(readQueue(), [request])
    }

    // MARK: - Set External Id.

    @MainActor
    func testSetExternalId() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setExternalId("external-blob")) {
            $0.externalId = "external-blob"
            $0.pushTokenData = nil
        }
        var expectedState = initialState
        expectedState.externalId = "external-blob"
        let request = expectedState.buildTokenRequest(
            apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement
        )
        XCTAssertEqual(readQueue(), [request])
    }

    // MARK: - Set Push Token

    @MainActor
    func testSetPushToken() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        initialState.flushing = false
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let pushTokenRequest = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blobtoken", enablement: .authorized)
        _ = await store.send(.setPushToken("blobtoken", .authorized))
        XCTAssertEqual(readQueue(), [pushTokenRequest])

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = [pushTokenRequest]
        }

        await store.receive(.sendRequest)

        _ = await store.receive(.deQueueCompletedResults(pushTokenRequest)) {
            $0.flushing = false
            $0.requestsInFlight = []
            $0.pushTokenData = PushTokenData(pushToken: "blobtoken", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.appContextInfo()))
        }
    }

    @MainActor
    func testSetPushTokenEnablementChanged() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData?.pushEnablement = .denied
        initialState.flushing = false
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let pushTokenRequest = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: .authorized
        )

        _ = await store.send(.setPushToken(initialState.pushTokenData!.pushToken, .authorized))
        XCTAssertEqual(readQueue(), [pushTokenRequest])

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = [pushTokenRequest]
        }

        await store.receive(.sendRequest)

        _ = await store.receive(.deQueueCompletedResults(pushTokenRequest)) {
            $0.flushing = false
            $0.requestsInFlight = []
            $0.pushTokenData = PushTokenData(
                pushToken: initialState.pushTokenData!.pushToken,
                pushEnablement: .authorized,
                pushBackground: initialState.pushTokenData!.pushBackground,
                deviceData: initialState.pushTokenData!.deviceData
            )
        }
    }

    @MainActor
    func testSetPushTokenMultipleTimes() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        initialState.flushing = false
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let pushTokenRequest = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blobtoken", enablement: .authorized)

        _ = await store.send(.setPushToken("blobtoken", .authorized))
        XCTAssertEqual(readQueue(), [pushTokenRequest])

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = [pushTokenRequest]
        }

        await store.receive(.sendRequest)

        _ = await store.receive(.deQueueCompletedResults(pushTokenRequest)) {
            $0.flushing = false
            $0.requestsInFlight = []
            $0.pushTokenData = PushTokenData(pushToken: "blobtoken", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.appContextInfo()))
        }
        _ = await store.send(.setPushToken("blobtoken", .authorized))
    }

    // MARK: - Set Push Enablement

    @MainActor
    func testSetPushEnablementPushTokenIsNil() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.setPushEnablement(.authorized))
    }

    @MainActor
    func testSetPushEnablementChanged() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData?.pushEnablement = .denied
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
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
        XCTAssertEqual(readQueue(), [pushTokenRequest])
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
        // QueueStore registry, which would otherwise drop the spy injected here.
        let readQueue = seedTestQueueStore(apiKey: apiKey, initial: [request])

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
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!, initial: [request, request2])
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
        seedTestQueueStore(apiKey: initialState.apiKey!, initial: [request, request2])
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
        seedTestQueueStore(apiKey: initialState.apiKey!, initial: [request, request2])
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
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
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
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
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
            let loc = Profile.test.location!
            XCTAssertEqual(attrs.location?.city, loc.city)
            XCTAssertEqual(attrs.location?.region, loc.region!)
            XCTAssertEqual(attrs.location?.address1, loc.address1!)
            XCTAssertEqual(attrs.location?.address2, loc.address2!)
            XCTAssertEqual(attrs.location?.zip, loc.zip!)
            XCTAssertEqual(attrs.location?.country, loc.country!)
            XCTAssertEqual(attrs.location?.latitude, loc.latitude!)
            XCTAssertEqual(attrs.location?.longitude, loc.longitude!)
            XCTAssertEqual(attrs.title, Profile.test.title)
            XCTAssertEqual(attrs.organization, Profile.test.organization)
            XCTAssertEqual(attrs.firstName, Profile.test.firstName)
            XCTAssertEqual(attrs.lastName, Profile.test.lastName)
            XCTAssertEqual(attrs.image, Profile.test.image)

            if let customProperties = attrs.properties.value as? [String: Any],
               let foo = customProperties["foo"] as? Int {
                XCTAssertEqual(foo, 20)
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

    // MARK: - Test set profile

    @MainActor
    func testSetProfileWithExistingProperties() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.enqueueProfile(Profile(email: "foo"))) {
            $0.phoneNumber = nil
            $0.email = "foo"
            $0.pushTokenData = nil
        }
    }

    @MainActor
    func testSetProfileWithAllProfileIdentifiersAndProperties() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.enqueueProfile(Profile.test)) {
            $0.email = Profile.test.email
            $0.phoneNumber = Profile.test.phoneNumber
            $0.externalId = Profile.test.externalId
            // No reset — state had no prior identifiers (isIdentified = false),
            // so pushTokenData stays on state.
        }
        let request = KlaviyoRequest(
            endpoint: .registerPushToken(
                initialState.apiKey!,
                PushTokenPayload(
                    pushToken: initialState.pushTokenData!.pushToken,
                    enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                    background: initialState.pushTokenData!.pushBackground.rawValue,
                    profile: ProfilePayload(
                        Profile.test,
                        anonymousId: initialState.anonymousId!
                    )
                )
            )
        )
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testCreateProfileWithTrailingWhitespaceProperties() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off
        _ = await store.send(.enqueueProfile(Profile(email: "foo@blob.com ", phoneNumber: "+19999999999     ", externalId: "abcdefg    "))) {
            $0.phoneNumber = "+19999999999"
            $0.email = "foo@blob.com"
            $0.externalId = "abcdefg"
            // No reset — state had no prior identifiers (isIdentified = false),
            // so pushTokenData stays on state. The reducer builds the request inline
            // using the captured pushTokenData without clearing it from state.
        }
        let request = KlaviyoRequest(
            endpoint: .registerPushToken(
                initialState.apiKey!,
                PushTokenPayload(
                    pushToken: initialState.pushTokenData!.pushToken,
                    enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                    background: initialState.pushTokenData!.pushBackground.rawValue,
                    profile: ProfilePayload(
                        Profile(
                            email: "foo@blob.com", phoneNumber: "+19999999999", externalId: "abcdefg"
                        ),
                        anonymousId: store.state.anonymousId!
                    )
                )
            )
        )
        XCTAssertEqual(readQueue(), [request])
    }

    // MARK: - Test enqueue event

    @MainActor
    func testEnqueueEvents() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

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
            let request = try KlaviyoRequest(
                endpoint: .createEvent(
                    XCTUnwrap(store.state.apiKey),
                    CreateEventPayload(
                        data: CreateEventPayload.Event(
                            name: eventName.value,
                            properties: event.properties,
                            phoneNumber: store.state.phoneNumber,
                            anonymousId: initialState.anonymousId!,
                            time: event.time,
                            pushToken: initialState.pushTokenData!.pushToken
                        )
                    )
                ),
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
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        await store.send(.enqueueEvent(.test))

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1, "pre-init event is buffered, not dropped or queued")
    }

    @MainActor
    func testPreInitBufferedEventDrainsIntoQueueOnInit() async throws {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // Buffer an event pre-init (no apiKey known yet).
        RequestEnqueuer.enqueueEvent(.test)
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)

        // Record every request the QueueStore ever persists, so the assertion is robust against the
        // post-init flush leasing (then dequeuing) the drained request out of the live backing array.
        let recorded = registerRecordingQueueStore(apiKey: TEST_API_KEY)

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
        // drainBuffer (run inside .initialize) enqueued the buffered event into the QueueStore for
        // this apiKey (it was persisted at some point), and trimmed the buffer.
        XCTAssertTrue(
            recorded().contains(expectedRequest),
            "buffered event was drained into the QueueStore at init"
        )
        XCTAssertTrue(
            UnattributedBuffer.shared.drainSnapshot().requests.isEmpty,
            "buffer is trimmed after draining into the queue"
        )
    }

    // MARK: - Test enqueue aggregate event

    @MainActor
    func testEnqueueAggregateEvent() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
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
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()

        let data = Data()
        // Buffer an aggregate event pre-init (no apiKey known yet).
        RequestEnqueuer.enqueueAggregateEvent(data)
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)

        // Record every persisted request (robust against the post-init flush lease/dequeue).
        let recorded = registerRecordingQueueStore(apiKey: TEST_API_KEY)

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

        let request = try KlaviyoRequest(
            endpoint: .aggregateEvent(TEST_API_KEY, AggregateEventPayload(data))
        )
        XCTAssertTrue(
            recorded().contains(request),
            "buffered aggregate event drained into the QueueStore at init"
        )
        XCTAssertTrue(UnattributedBuffer.shared.drainSnapshot().requests.isEmpty)
    }

    @MainActor
    func testPrioritizedEventsAreInsertedAtFrontOfQueue() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false

        // Add some existing requests to the queue
        let existingRequest1 = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let existingRequest2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "token1", enablement: .authorized)
        seedTestQueueStore(apiKey: initialState.apiKey!, initial: [existingRequest1, existingRequest2])

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
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(email: "test@example.com", anonymousId: anonymousId)
        )
        let readQueue = seedTestQueueStore(apiKey: apiKey)
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
        let readQueue = seedTestQueueStore(apiKey: apiKey)
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
    func testEnqueueSubscriptionUninitializedWarnsAndDoesNotEnqueue() async throws {
        let initialState = INITILIZING_TEST_STATE()
        let apiKey = try XCTUnwrap(initialState.apiKey)
        let readQueue = seedTestQueueStore(apiKey: apiKey)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let warningExpectation = expectSubscriptionWarning(containing: "initialize")

        await store.send(.enqueueSubscription(Subscription.allAvailableMarketing(listId: "list-123")))
        await fulfillment(of: [warningExpectation], timeout: 1.0)
        XCTAssertTrue(readQueue().isEmpty, "nothing should be enqueued before initialization")
        XCTAssertTrue(UnattributedBuffer.shared.drainSnapshot().requests.isEmpty,
                      "nothing should be buffered for pre-init subscriptions")
    }

    @MainActor
    func testEnqueueSubscriptionMissingIdentifiersDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "at least one identifier")
        let initialState = INITIALIZED_TEST_STATE()
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
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
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(phoneNumber: "+15005550006", anonymousId: anonymousId)
        )
        let readQueue = seedTestQueueStore(apiKey: apiKey)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        await store.send(.enqueueSubscription(subscription))
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testEnqueueSubscriptionEmptyChannelsDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "none were enabled")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init())))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(readQueue().isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionEmailChannelWithoutEmailDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "requires an email")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "+15005550006"
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init(email: .marketing))))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(readQueue().isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionPhoneChannelWithoutPhoneDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "requires a phone number")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!)
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
    /// so front-insertion (high priority) vs. append (standard) is observable. Returns the
    /// store together with the seeded request for identity assertions.
    @MainActor
    private func makePriorityTestStore() -> PriorityTestScaffold {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let existingRequest = initialState.buildProfileRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!
        )
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!, initial: [existingRequest])
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
        let store = TestStore(initialState: seeded, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.resetProfile)

        XCTAssertNil(IdentityStore.shared.current.email, "reset clears identity through the store")
        XCTAssertNotNil(IdentityStore.shared.current.anonymousId)
        XCTAssertNotEqual(
            IdentityStore.shared.current.anonymousId, "anon-before",
            "reset of an identified profile mints a fresh anonymousId via IdentityStore"
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
        let recorded = registerRecordingQueueStore(apiKey: TEST_API_KEY)

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
}
