//
//  StateManagementEdgeCaseTests.swift
//  Move some state management that feel edge casey over here. These are less likely to happen but still want to cover the code.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

class StateManagementEdgeCaseTests: StateManagementTestCase {
    // MARK: - initialization

    @MainActor
    func testInitializeWhileInitializing() async throws {
        let initialState = KlaviyoState(requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        environment.fileClient.fileExists = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return true
        }

        let apiKey = "fake-key"

        // Avoids a warning in xcode despite the result being discardable.
        _ = await store.send(.initialize(apiKey)) {
            $0.apiKey = apiKey
            $0.initalizationState = .initializing
        }

        // Should be no state change here.
        _ = await store.send(.initialize(apiKey))
    }

    @MainActor
    func testInitializeAfterInitialized() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let oldApiKey = initialState.apiKey!
        let newApiKey = "new-api-key"
        // Single shared queue: both the unregister (built while state.apiKey is still the old key)
        // and the token-register (built after the switch to the new key) land in the same queue.
        let readQueue = seedTestQueueStore(apiKey: oldApiKey)

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Using the same key shouldn't do much
        _ = await store.send(.initialize(oldApiKey))

        // Using a new key should update the key and generate two requests
        var mutableState = initialState
        _ = await store.send(.initialize(newApiKey)) {
            $0.apiKey = newApiKey
        }
        // Company switch prompts an immediate flush so the unregister drains promptly.
        await store.receive(.flushQueue)
        // Unregister must carry .high priority so it is sent before normal queued requests.
        let unregister = KlaviyoRequest(
            endpoint: mutableState.buildUnregisterRequest(
                apiKey: oldApiKey, anonymousId: store.state.anonymousId!,
                pushToken: initialState.pushTokenData!.pushToken
            ).endpoint,
            priority: .high
        )
        let tokenRequest = mutableState.buildTokenRequest(
            apiKey: newApiKey, anonymousId: store.state.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: initialState.pushTokenData!.pushEnablement
        )
        // Both requests land in the single shared queue; the unregister (enqueued first) precedes
        // the token-register (enqueued after the apiKey switch).
        XCTAssertEqual(readQueue(), [unregister, tokenRequest],
                       "both the unregister and register land in the single shared queue")
        XCTAssertEqual(readQueue().first?.priority, .high, "unregister must carry .high priority")
    }

    @MainActor
    func testColdStartCompanySwitchPreservesAndReregistersToken() async throws {
        resetCanonicalCoreStores()
        QueueStore.resetRegistry()
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "old-key"))
        IdentityStore.shared.update(ProfileData(email: "a@x.com", externalId: "user-A", anonymousId: "anon-A"))
        let token = PushTokenData(
            pushToken: "tok-1",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
        IdentityStore.shared.updatePushToken(token)
        let readQueue = registerRecordingQueueStore(apiKey: "new-key")

        let store = TestStore(initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer())
        store.exhaustivity = .off
        await store.send(.initialize("new-key"))
        await store.receive(
            .completeInitialization(KlaviyoState(requestsInFlight: [])),
            timeout: TIMEOUT_NANOSECONDS
        )

        // Token PRESERVED (regression: today it is cleared).
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, "tok-1")
        let endpoints = readQueue().map(\.endpoint)
        XCTAssertTrue(
            endpoints.contains { if case .unregisterPushToken = $0 { return true } else { return false } },
            "old-company unregister enqueued"
        )
        XCTAssertTrue(
            endpoints.contains { if case .registerPushToken = $0 { return true } else { return false } },
            "token re-registered under the new company"
        )
    }

    // MARK: - Send Request

    @MainActor
    func testSendRequestBeforeInitialization() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: true)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest)
    }

    // MARK: - Complete Initialization

    @MainActor
    func testCompleteInitializationWhileAlreadyInitialized() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u",
                                                         externalId: "external-id", requestsInFlight: [],
                                                         initalizationState: .initialized,
                                                         flushing: true), reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.completeInitialization(initialState))
    }

    @MainActor
    func testCompleteInitializationWithExistingIdentifiers() async throws {
        let setBadgeExpectation = expectation(description: "BadgeManager.setBadgeCount(0) called on start")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }

        let apiKey = "fake-key"
        // The anonymousId is hydrated from the canonical `IdentityStore` during
        // `.completeInitialization` (not carried in the action payload). Seed it here so the
        // resulting state's anonymousId is the expected "foo".
        IdentityStore.shared.update(ProfileData(anonymousId: "foo"))
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: "foo", requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u",
                                                         externalId: "external-id", requestsInFlight: [],
                                                         initalizationState: .initializing,
                                                         flushing: true), reducer: KlaviyoReducer())
        // Attempting to get more coverage
        _ = await store.send(.completeInitialization(initialState)) {
            $0.initalizationState = .initialized
            $0.anonymousId = "foo"
        }
        await store.receive(.start)
        await store.receive(.flushQueue)
        await store.receive(.setPushEnablement(PushEnablement.authorized))
        await fulfillment(of: [setBadgeExpectation], timeout: 1)
    }

    // MARK: - Set Email

    @MainActor
    func testSetEmailUninitializedBuffersProfileWithEmail() async throws {
        // the pre-init setter must push the just-set identifier to IdentityStore BEFORE
        // enqueueProfile reads it, so the buffered profile carries the email (not a stale/empty one).
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: [], initalizationState: .uninitialized),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.setEmail("test@blob.com"))

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1, "pre-init setEmail buffers a profile sync")
        guard case let .profile(payload) = buffered.first else {
            return XCTFail("expected a buffered profile request")
        }
        XCTAssertEqual(
            payload.data.attributes.email, "test@blob.com",
            "the just-set email reaches the buffered profile payload"
        )
    }

    @MainActor
    func testSetEmailMissingAnonymousIdStillSetsEmail() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("test@blob.com")) {
            $0.email = "test@blob.com"
        }
    }

    @MainActor
    func testSetEmptyEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail(""))
    }

    @MainActor
    func testSetEmailWithWhiteSpace() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("        "))
    }

    @MainActor
    func testSetEmailWithTrailingWhiteSpace() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.setEmail("test@blob.com        ")) {
            $0.email = "test@blob.com"
        }
    }

    // MARK: - Set External Id

    @MainActor
    func testSetExternalIdUninitializedBuffersProfileWithExternalId() async throws {
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: [], initalizationState: .uninitialized),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.setExternalId("external-blob-id"))

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1)
        guard case let .profile(payload) = buffered.first else {
            return XCTFail("expected a buffered profile request")
        }
        XCTAssertEqual(payload.data.attributes.externalId, "external-blob-id")
    }

    @MainActor
    func testSetExternalIdMissingAnonymousIdStillSetsExternalId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("external-blob-id")) {
            $0.externalId = "external-blob-id"
        }
    }

    @MainActor
    func testSetEmptyExternalId() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId(""))
    }

    @MainActor
    func testSetExternalIdWithWhiteSpaces() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("      "))
    }

    @MainActor
    func testSetExternalIdWithTrailingWhiteSpace() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.setExternalId("external-blob-id        ")) {
            $0.externalId = "external-blob-id"
        }
    }

    // MARK: - Set Phone number

    @MainActor
    func testSetPhoneNumberUninitializedBuffersProfileWithPhoneNumber() async throws {
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: [], initalizationState: .uninitialized),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u"))

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1)
        guard case let .profile(payload) = buffered.first else {
            return XCTFail("expected a buffered profile request")
        }
        XCTAssertEqual(payload.data.attributes.phoneNumber, "1-800-Blobs4u")
    }

    @MainActor
    func testSetPhoneNumberMissingApiKeyStillSetsPhoneNumber() async throws {
        let initialState = KlaviyoState(anonymousId: environment.uuid().uuidString,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u")) {
            $0.phoneNumber = "1-800-Blobs4u"
        }
    }

    @MainActor
    func testSetEmptyPhoneNumber() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber(""))
    }

    @MainActor
    func testSetPhoneNumberWithWhiteSpaces() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("       "))
    }

    @MainActor
    func testSetPhoneNumberWithTrailingWhiteSpace() async throws {
        let initialState = KlaviyoState(anonymousId: environment.uuid().uuidString,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u        ")) {
            $0.phoneNumber = "1-800-Blobs4u"
        }
    }

    // MARK: - Set Push Token

    @MainActor
    func testSetPushTokenUninitializedRoutesToBuffer() async throws {
        let initialState = KlaviyoState(anonymousId: environment.uuid().uuidString,
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPushToken("blob_token", .authorized))
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)
    }

    @MainActor
    func testAutomaticPushTokenUninitializedRoutesToBuffer() async throws {
        let initialState = KlaviyoState(
            anonymousId: environment.uuid().uuidString,
            requestsInFlight: [],
            initalizationState: .uninitialized,
            flushing: false
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setAutomaticPushToken("automatic-token", .authorized))
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)
    }

    @MainActor
    func testSetPushTokenWithMissingAnonymousId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage. With no apiKey in SDKConfigStore the token
        // routes to the durable UnattributedBuffer rather than being parked in state.
        _ = await store.send(.setPushToken("blob_token", .authorized))
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)
    }

    // MARK: - Stop

    @MainActor
    func testStopUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.stop)
    }

    @MainActor
    func testStopInitializing() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        requestsInFlight: [],
                                        initalizationState: .initializing,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.stop)
    }

    // MARK: - Start

    @MainActor
    func testStartUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.start)
    }

    // MARK: - Default Badge Clearing

    @MainActor
    func testDefaultBadgeClearingOn() async throws {
        let apiKey = "fake-key"
        environment.getBadgeAutoClearingSetting = { true }
        let setBadgeExpectation = XCTestExpectation(description: "Should set badge to 0")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }
        // Seed the canonical IdentityStore so `.completeInitialization` hydrates anonymousId "foo".
        IdentityStore.shared.update(ProfileData(anonymousId: "foo"))
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: "foo", requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u",
                                                         externalId: "external-id", requestsInFlight: [],
                                                         initalizationState: .initializing,
                                                         flushing: true), reducer: KlaviyoReducer())
        // Attempting to get more coverage
        _ = await store.send(.completeInitialization(initialState)) {
            $0.initalizationState = .initialized
            $0.anonymousId = "foo"
        }
        await store.receive(.start)
        await store.receive(.flushQueue)
        await store.receive(.setPushEnablement(PushEnablement.authorized))
        await fulfillment(of: [setBadgeExpectation], timeout: 1, enforceOrder: true)
    }

    // MARK: - Default Badge Clearing Turned Off

    @MainActor
    func testDefaultBadgeClearingOff() async {
        let apiKey = "fake-key"
        environment.getBadgeAutoClearingSetting = { false }
        let notCalledExpectation = XCTestExpectation(description: "Should not set badge to 0")
        notCalledExpectation.isInverted = true
        let syncExpectation = XCTestExpectation(description: "Should sync badge count")
        BadgeManager.setBadgeCountSpy = { _ in notCalledExpectation.fulfill() }
        BadgeManager.syncBadgeCountSpy = { syncExpectation.fulfill() }
        // Seed the canonical IdentityStore so `.completeInitialization` hydrates anonymousId "foo".
        IdentityStore.shared.update(ProfileData(anonymousId: "foo"))
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: "foo", requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u",
                                                         externalId: "external-id", requestsInFlight: [],
                                                         initalizationState: .initializing,
                                                         flushing: true), reducer: KlaviyoReducer())
        // Attempting to get more coverage
        _ = await store.send(.completeInitialization(initialState)) {
            $0.initalizationState = .initialized
            $0.anonymousId = "foo"
        }
        await store.receive(.start)
        await store.receive(.flushQueue)
        await store.receive(.setPushEnablement(PushEnablement.authorized))
        await fulfillment(of: [notCalledExpectation, syncExpectation], timeout: 1, enforceOrder: true)
    }

    // MARK: - Network Status Changed

    @MainActor
    func testNetworkStatusChangedUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.networkConnectivityChanged(.reachableViaWWAN))
    }

    // MARK: - Flush queue while offline during retry backoff

    @MainActor
    func testFlushQueueWhileOfflineDuringBackoffDoesNotTrap() async {
        // Offline + backoff: the priority path can dispatch `.flushQueue` while `flushInterval` is
        // `.infinity`, where the backoff countdown used to trap converting it to `Int`.
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryState = .retryWithBackoff(
            requestCount: 1,
            totalRetryCount: 1,
            currentBackoff: 30
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.networkConnectivityChanged(.notReachable)) {
            $0.flushInterval = Double.infinity
        }
        // Also clears `flushing` — otherwise `.flushQueue` bails early and this test is vacuous.
        _ = await store.receive(.cancelInFlightRequests) {
            $0.flushing = false
        }

        // No state mutation and no follow-on effect: notably `retryState` keeps its backoff.
        _ = await store.send(.flushQueue)
    }

    @MainActor
    func testFlushQueueWhileOfflineWithoutBackoffDoesNotDrainQueue() async {
        // The guard sits above the backoff block, so it also stops the non-backoff `.retry` path —
        // which never crashed, but draining while offline only burns attempts. Pins that half:
        // the queue must stay put rather than moving into requestsInFlight.
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryState = .retry(1)
        let request = initialState.buildProfileRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!
        )
        let readQueue = seedTestQueueStore(apiKey: initialState.apiKey!, initial: [request])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.networkConnectivityChanged(.notReachable)) {
            $0.flushInterval = Double.infinity
        }
        _ = await store.receive(.cancelInFlightRequests) {
            $0.flushing = false
        }

        // Queue is non-empty on purpose — with an empty queue `.flushQueue` returns early anyway
        // and this test would pass with or without the guard.
        _ = await store.send(.flushQueue)
        XCTAssertEqual(readQueue(), [request], "queue must not drain while offline")
    }

    // MARK: - Missing api key for token request

    @MainActor
    func testTokenRequestMissingApiKey() async {
        let initialState = KlaviyoState(
            anonymousId: environment.uuid().uuidString,
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: false
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage on it. Missing apiKey → the token routes to
        // the durable UnattributedBuffer rather than being parked in state.
        _ = await store.send(.setPushToken("blobtoken", .authorized))
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)
    }
}
