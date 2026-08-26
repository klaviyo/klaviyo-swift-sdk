//
//  StateManagementEdgeCaseTests.swift
//  Move some state management that feel edge casey over here. These are less likely to happen but still want to cover the code.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

class StateManagementEdgeCaseTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        BadgeManager.resetToProduction()
    }

    @MainActor
    override func tearDown() async throws {
        BadgeManager.resetToProduction()
    }

    // MARK: - initialization

    @MainActor
    func testInitializeWhileInitializing() async throws {
        let initialState = KlaviyoState(queue: [], requestsInFlight: [])
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
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Using the same key shouldn't do much
        _ = await store.send(.initialize(initialState.apiKey!))

        let newApiKey = "new-api-key"
        // Using a new key should update the key and generate two requests
        _ = await store.send(.initialize(newApiKey)) {
            $0.queue = [$0.buildUnregisterRequest(apiKey: $0.apiKey!, anonymousId: $0.anonymousId!, pushToken: $0.pushTokenData!.pushToken),
                        $0.buildTokenRequest(apiKey: newApiKey, anonymousId: $0.anonymousId!, pushToken: $0.pushTokenData!.pushToken, enablement: $0.pushTokenData!.pushEnablement)]
            $0.apiKey = newApiKey
        }
    }

    // MARK: - Send Request

    @MainActor
    func testSendRequestBeforeInitialization() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
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
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
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
                                        anonymousId: "foo", queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
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
    func testSetEmailUninitializedDoesNotAddToPendingRequest() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.emitDeveloperWarning = { _ in
            // Would really fatalError - not happening because we can't do that in tests so we fake it.
            expection.fulfill()
        }
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("test@blob.com"))

        await fulfillment(of: [expection])
    }

    @MainActor
    func testSetEmailMissingAnonymousIdStillSetsEmail() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
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
                                        queue: [],
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
    func testSetExternalIdUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("external-blob-id"))
    }

    @MainActor
    func testSetExternalIdMissingAnonymousIdStillSetsExternalId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
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
                                        queue: [],
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
    func testSetPhoneNumberUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u"))
    }

    @MainActor
    func testSetPhoneNumberMissingApiKeyStillSetsPhoneNumber() async throws {
        let initialState = KlaviyoState(anonymousId: environment.uuid().uuidString,
                                        queue: [],
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
                                        queue: [],
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
    func testSetPushTokenUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPushToken("blob_token", .authorized))
    }

    @MainActor
    func testAutomaticPushTokenUninitializedAddsToDedicatedPendingRequest() async throws {
        let store = TestStore(initialState: KlaviyoState(queue: []), reducer: KlaviyoReducer())

        _ = await store.send(.setAutomaticPushToken("automatic-token", .authorized)) {
            $0.pendingRequests = [.automaticPushToken("automatic-token", .authorized)]
        }
    }

    @MainActor
    func testAutomaticPushTokenBufferKeepsOnlyLatestAutomaticToken() async throws {
        let store = TestStore(initialState: KlaviyoState(queue: []), reducer: KlaviyoReducer())

        _ = await store.send(.setAutomaticPushToken("old-token", .authorized)) {
            $0.pendingRequests = [.automaticPushToken("old-token", .authorized)]
        }
        _ = await store.send(.setAutomaticPushToken("new-token", .denied)) {
            $0.pendingRequests = [.automaticPushToken("new-token", .denied)]
        }
    }

    @MainActor
    func testAutomaticPushTokenDoesNotCoalesceManualPendingToken() async throws {
        let initialState = KlaviyoState(
            queue: [],
            initalizationState: .initializing,
            pendingRequests: [.pushToken("manual-token", .authorized)]
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setAutomaticPushToken("automatic-token", .provisional)) {
            $0.pendingRequests.append(.automaticPushToken("automatic-token", .provisional))
        }
    }

    /// Pins that the automatic-token replacement happens in place, not via remove-then-append.
    /// `testAutomaticPushTokenBufferKeepsOnlyLatestAutomaticToken` starts from an empty queue,
    /// where index 0 is both the in-place slot and the append slot, so it can't tell the two
    /// implementations apart. Buffering the automatic token ahead of another pending request
    /// makes the distinction observable: a remove-then-append implementation would silently
    /// reorder the queue by moving the replaced token to the end.
    @MainActor
    func testAutomaticPushTokenReplacementKeepsQueuePosition() async throws {
        let initialState = KlaviyoState(
            queue: [],
            initalizationState: .initializing,
            pendingRequests: [
                .automaticPushToken("old-token", .authorized),
                .pushToken("manual-token", .authorized)
            ]
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setAutomaticPushToken("new-token", .denied)) {
            $0.pendingRequests = [
                .automaticPushToken("new-token", .denied),
                .pushToken("manual-token", .authorized)
            ]
        }
    }

    @MainActor
    func testSetPushTokenWithMissingAnonymousId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage
        _ = await store.send(.setPushToken("blob_token", .authorized)) {
            $0.pendingRequests = [.pushToken("blob_token", .authorized)]
        }
    }

    // MARK: - Stop

    @MainActor
    func testStopUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
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
                                        queue: [],
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
                                        queue: [],
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
                                        anonymousId: "foo", queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
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
                                        anonymousId: "foo", queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
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
                                        queue: [],
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
        initialState.queue = [request]
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
    }

    // MARK: - Missing api key for token request

    @MainActor
    func testTokenRequestMissingApiKey() async {
        let initialState = KlaviyoState(
            anonymousId: environment.uuid().uuidString,
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: false
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage on it.
        _ = await store.send(.setPushToken("blobtoken", .authorized)) {
            $0.pendingRequests = [.pushToken("blobtoken", .authorized)]
        }
    }

    // MARK: - set enqueue event uninitialized

    @MainActor
    func testHighPriorityEventUninitializedAddsToPendingRequests() async throws {
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())
        // High-priority events bypass the initialization gate and are held as pending.
        let event = Event(name: ._openedPush, priority: .high)
        _ = await store.send(.enqueueEvent(event)) {
            $0.pendingRequests = [.event(event)]
        }
    }

    @MainActor
    func testStandardPriorityEventUninitializedEmitsWarning() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.emitDeveloperWarning = { _ in
            // Would really runTimeWarn - not happening because we can't do that in tests so we fake it.
            expection.fulfill()
        }
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())

        // Standard-priority events (including ._openedPush created without .high) require initialization.
        for eventName in Event.EventName.allCases {
            let event = Event(name: eventName)
            _ = await store.send(.enqueueEvent(event))
        }

        await fulfillment(of: [expection])
    }

    // MARK: - set profile uninitialized

    @MainActor
    func testSetProfileUnitialized() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.emitDeveloperWarning = { _ in
            // Would really runTimeWarn - not happening because we can't do that in tests so we fake it.
            expection.fulfill()
        }
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())
        let profile = Profile(email: "foo")
        _ = await store.send(.enqueueProfile(profile))
        await fulfillment(of: [expection])
    }

    @MainActor
    func testSetProfileWithEmptyStringIdentifiers() async throws {
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "foo@bar.com",
            anonymousId: environment.uuid().uuidString,
            phoneNumber: "99999999",
            externalId: "12345",
            pushTokenData: .init(pushToken: "blob_token",
                                 pushEnablement: .authorized,
                                 pushBackground: .available,
                                 deviceData: .init(context: environment.appContextInfo())),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueProfile(Profile(email: "", phoneNumber: "", externalId: ""))) {
            $0.email = nil // since we reset state
            $0.phoneNumber = nil // since we reset state
            $0.externalId = nil // since we reset state
            $0.enqueueProfileOrTokenRequest()
            $0.pushTokenData = nil
        }
    }

    // MARK: - enqueueProfile: conditional reset (push-token storm fix)

    @MainActor
    func testSetProfileSameIdentifiersDoesNotReset() async throws {
        // When setProfile is called with the same identifiers that are already on state,
        // reset() should NOT fire — anonymousId stays the same, no spurious push-token request.
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "same@email.com",
            anonymousId: environment.uuid().uuidString,
            phoneNumber: "+15555555555",
            externalId: "ext-123",
            pushTokenData: .init(pushToken: "blob_token",
                                 pushEnablement: .authorized,
                                 pushBackground: .available,
                                 deviceData: .init(context: environment.appContextInfo())),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Same identifiers + no non-identifier attributes → no reset, no API call, no state change.
        // Nothing changed, so there's no reason to hit the network.
        // The pushTokenData and anonymousId both remain untouched on state.
        _ = await store.send(.enqueueProfile(Profile(email: "same@email.com", phoneNumber: "+15555555555", externalId: "ext-123")))
    }

    @MainActor
    func testSetProfileDifferentIdentifiersResetsState() async throws {
        // When setProfile is called with different identifiers, reset() SHOULD fire,
        // regenerating the anonymousId and clearing pushTokenData.
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "old@email.com",
            anonymousId: environment.uuid().uuidString,
            phoneNumber: "+11111111111",
            externalId: "old-ext",
            pushTokenData: .init(pushToken: "blob_token",
                                 pushEnablement: .authorized,
                                 pushBackground: .available,
                                 deviceData: .init(context: environment.appContextInfo())),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueProfile(Profile(email: "new@email.com", phoneNumber: "+12222222222", externalId: "new-ext"))) {
            // reset() fires → identifiers cleared, then updateStateWithProfile sets new ones
            $0.email = "new@email.com"
            $0.phoneNumber = "+12222222222"
            $0.externalId = "new-ext"
            // pushTokenData cleared by reset
            $0.pushTokenData = nil
            // Since pushTokenData existed before reset, the reducer uses it to build a token request
            let request = KlaviyoRequest(
                endpoint: .registerPushToken(
                    TEST_API_KEY,
                    PushTokenPayload(
                        pushToken: initialState.pushTokenData!.pushToken,
                        enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                        background: initialState.pushTokenData!.pushBackground.rawValue,
                        profile: ProfilePayload(
                            Profile(email: "new@email.com", phoneNumber: "+12222222222", externalId: "new-ext"),
                            anonymousId: $0.anonymousId!
                        )
                    )
                )
            )
            $0.queue = [request]
        }
    }

    @MainActor
    func testSetProfileSameIdentifiersDifferentAttributesStillUpdates() async throws {
        // Same identifiers but different non-identifier attributes (e.g. firstName) —
        // should NOT reset, but attributes should still be sent in the profile request.
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "same@email.com",
            anonymousId: environment.uuid().uuidString,
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // No pushTokenData → a createProfile request is generated instead of registerPushToken
        let profile = Profile(email: "same@email.com", firstName: "NewName")
        _ = await store.send(.enqueueProfile(profile)) {
            // No reset (same email), so anonymousId unchanged
            // A createProfile request should be enqueued with the updated attributes
            let profilePayload = ProfilePayload(
                profile,
                email: $0.email,
                phoneNumber: $0.phoneNumber,
                externalId: $0.externalId,
                anonymousId: $0.anonymousId!
            )
            let request = KlaviyoRequest(
                endpoint: .createProfile(TEST_API_KEY, CreateProfilePayload(data: profilePayload))
            )
            $0.queue = [request]
        }
    }

    @MainActor
    func testSetProfilePartialIdentifierMatchStillResets() async throws {
        // If only one identifier changes (e.g. email changes, phone stays same),
        // reset should still fire.
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "old@email.com",
            anonymousId: environment.uuid().uuidString,
            phoneNumber: "+15555555555",
            pushTokenData: .init(pushToken: "blob_token",
                                 pushEnablement: .authorized,
                                 pushBackground: .available,
                                 deviceData: .init(context: environment.appContextInfo())),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Email changes, phone stays the same → identifiersChanged = true
        _ = await store.send(.enqueueProfile(Profile(email: "different@email.com", phoneNumber: "+15555555555"))) {
            // reset() fires
            $0.email = "different@email.com"
            $0.phoneNumber = "+15555555555"
            $0.pushTokenData = nil
            let request = KlaviyoRequest(
                endpoint: .registerPushToken(
                    TEST_API_KEY,
                    PushTokenPayload(
                        pushToken: initialState.pushTokenData!.pushToken,
                        enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                        background: initialState.pushTokenData!.pushBackground.rawValue,
                        profile: ProfilePayload(
                            Profile(email: "different@email.com", phoneNumber: "+15555555555"),
                            anonymousId: $0.anonymousId!
                        )
                    )
                )
            )
            $0.queue = [request]
        }
    }

    @MainActor
    func testSetProfileNilIdentifiersTriggersResetWhenStateHasIdentifiers() async throws {
        // All-nil incoming identifiers differ from non-nil state identifiers,
        // so reset fires — preserving the old "clobbering" setProfile behavior.
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "existing@email.com",
            anonymousId: environment.uuid().uuidString,
            phoneNumber: "+15555555555",
            externalId: "ext-id",
            pushTokenData: .init(pushToken: "blob_token",
                                 pushEnablement: .authorized,
                                 pushBackground: .available,
                                 deviceData: .init(context: environment.appContextInfo())),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Profile with all-nil identifiers → [nil,nil,nil] != [email,phone,extId] → reset fires
        let profile = Profile(firstName: "JustAName")
        _ = await store.send(.enqueueProfile(profile)) {
            // reset(preserveTokenData: false) fires → identifiers cleared, pushTokenData nil
            $0.email = nil
            $0.phoneNumber = nil
            $0.externalId = nil
            $0.pushTokenData = nil
            // pushTokenData existed before reset, so a token request is built with captured data
            let request = KlaviyoRequest(
                endpoint: .registerPushToken(
                    TEST_API_KEY,
                    PushTokenPayload(
                        pushToken: initialState.pushTokenData!.pushToken,
                        enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                        background: initialState.pushTokenData!.pushBackground.rawValue,
                        profile: ProfilePayload(profile, anonymousId: $0.anonymousId!)
                    )
                )
            )
            $0.queue = [request]
        }
    }

    @MainActor
    func testResetProfileStillClobbersAllState() async throws {
        // resetProfile() should always clobber all state, regardless of identifiers.
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "user@email.com",
            anonymousId: environment.uuid().uuidString,
            phoneNumber: "+15555555555",
            externalId: "ext-123",
            pushTokenData: .init(pushToken: "blob_token",
                                 pushEnablement: .authorized,
                                 pushBackground: .available,
                                 deviceData: .init(context: environment.appContextInfo())),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.resetProfile) {
            // reset(preserveTokenData: true) is the default for resetProfile
            $0.email = nil
            $0.phoneNumber = nil
            $0.externalId = nil
            $0.pendingProfile = nil
            // pushTokenData is preserved and a new token request is enqueued
            // anonymousId is regenerated since the profile was identified
            $0.pushTokenData = initialState.pushTokenData
            let request = KlaviyoRequest(
                endpoint: .registerPushToken(
                    TEST_API_KEY,
                    PushTokenPayload(
                        pushToken: initialState.pushTokenData!.pushToken,
                        enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                        background: initialState.pushTokenData!.pushBackground.rawValue,
                        profile: ProfilePayload(Profile(), anonymousId: $0.anonymousId!)
                    )
                )
            )
            $0.queue = [request]
        }
    }
}

extension Event.EventName: CaseIterable {
    public static var allCases: [KlaviyoCore.Event.EventName] {
        [._openedPush, .openedAppMetric, .viewedProductMetric, .addedToCartMetric, .startedCheckoutMetric, .customEvent("someEvent")]
    }
}
