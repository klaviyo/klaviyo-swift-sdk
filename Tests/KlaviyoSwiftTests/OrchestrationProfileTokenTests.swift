//
//  OrchestrationProfileTokenTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/14/26.
//
//  Parity coverage for the push-token, profile, and subscription reducer cases being ported into
//  `KlaviyoOrchestration` (Task 4b). These tests exercise the NEW orchestration functions directly,
//  reproducing the coverage that will be removed from `StateManagementTests` /
//  `StateManagementEnqueueEdgeCaseTests` when those files are deleted in a later task.

@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
import Foundation
import XCTest

class OrchestrationProfileTokenTests: StateManagementTestCase {
    // MARK: - Test lifecycle

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        // LifecycleState is a KlaviyoSwift singleton; reset so each test starts `.uninitialized`.
        LifecycleState.shared.reset()
    }

    // MARK: - Helpers

    /// Seeds a post-init state: apiKey in SDKConfigStore, identity + push token in IdentityStore,
    /// LifecycleState advanced to `.initialized`.
    @discardableResult
    private func seedPostInitWithToken(
        apiKey: String = TEST_API_KEY,
        anonymousId: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        pushToken: String = "blob_token"
    ) -> (apiKey: String, anonymousId: String, pushToken: String) {
        let resolvedAnon = anonymousId ?? environment.uuid().uuidString
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(ProfileData(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: resolvedAnon
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushToken,
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()
        return (apiKey, resolvedAnon, pushToken)
    }

    /// Builds the identity-only `registerPushToken` request expected after an identifier change.
    private func expectedIdentityOnlyTokenRequest(
        apiKey: String = TEST_API_KEY,
        anonymousId: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        tokenData: PushTokenData
    ) -> KlaviyoRequest {
        let payload = RequestFactory.tokenPayload(
            identity: PayloadIdentity(
                anonymousId: anonymousId,
                email: email,
                phoneNumber: phoneNumber,
                externalId: externalId
            ),
            pushToken: tokenData.pushToken,
            enablement: tokenData.pushEnablement,
            background: environment.getBackgroundSetting()
        )
        return KlaviyoRequest(endpoint: .registerPushToken(apiKey, payload))
    }

    /// Default push token data used in helpers.
    private var defaultTokenData: PushTokenData {
        PushTokenData(
            pushToken: "blob_token",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
    }

    // MARK: - setPushToken: dedup

    /// Identical call → dedup → no enqueue, no store write.
    @MainActor
    func testSetPushTokenDedupIsNoOp() {
        let tokenData = defaultTokenData
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: environment.uuid().uuidString))
        // Pre-seed the canonical token to the exact value we're about to set.
        IdentityStore.shared.updatePushToken(tokenData)
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPushToken(tokenData.pushToken, tokenData.pushEnablement)

        XCTAssertTrue(readQueue().isEmpty,
                      "identical setPushToken must be deduped — nothing enqueued")
    }

    // MARK: - setPushToken: post-init → QueueStore

    /// Post-init + new token → enqueues a `registerPushToken` via `QueueStore`.
    @MainActor
    func testSetPushTokenPostInitEnqueuesViaQueueStore() {
        let (apiKey, anonymousId, _) = seedPostInitWithToken()
        // Clear the token so the new value isn't deduped.
        IdentityStore.shared.updatePushToken(nil)
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPushToken("new-tok", .authorized)

        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, "new-tok",
                       "new token must be persisted to IdentityStore")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "post-init setPushToken must enqueue exactly one token request")
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken, got \(queued.first?.endpoint as Any)")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, "new-tok")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
    }

    /// Enablement change on an existing token → updates IdentityStore and enqueues via QueueStore.
    @MainActor
    func testSetPushTokenEnablementChangedPostInitEnqueues() {
        let (apiKey, anonymousId, pushTok) = seedPostInitWithToken()
        // Override the stored token with .denied so it differs from .authorized we'll set.
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushTok,
            pushEnablement: .denied,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPushToken(pushTok, .authorized)

        XCTAssertEqual(IdentityStore.shared.pushToken?.pushEnablement, .authorized,
                       "updated enablement must be persisted")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushTok)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
    }

    // MARK: - setPushToken: warm-start (LifecycleState == .uninitialized)

    /// Warm-start: SDKConfigStore has a persisted apiKey but initialize() has NOT been called →
    /// falls through to `RequestEnqueuer` (parity with old reducer's `state.apiKey == nil` branch).
    @MainActor
    func testSetPushTokenWarmStartPreInitRoutesToRequestEnqueuer() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // LifecycleState stays .uninitialized (reset in setUp, not advanced here).
        XCTAssertEqual(LifecycleState.shared.current, .uninitialized,
                       "precondition: warm-start requires LifecycleState == .uninitialized")
        // Persist apiKey in SDKConfigStore (warm start: prior launch left it behind).
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-warm"))
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPushToken("warm-tok", .authorized)

        // RequestEnqueuer re-gates on SDKConfigStore: since apiKey is present, the token lands
        // directly in QueueStore (not the UnattributedBuffer). The endpoint must be a push-token
        // registration, NOT a createProfile (that's the key parity boundary).
        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "warm-start setPushToken must enqueue exactly one request")
        guard case .registerPushToken = queued.first?.endpoint else {
            return XCTFail(
                "warm-start setPushToken must enqueue registerPushToken (via RequestEnqueuer), "
                    + "got \(queued.first?.endpoint as Any)"
            )
        }
    }

    /// Pre-init (no apiKey anywhere) → token ends up in UnattributedBuffer.
    @MainActor
    func testSetPushTokenPreInitNoApiKeyBuffersInUnattributedBuffer() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // LifecycleState stays .uninitialized, SDKConfigStore has NO apiKey.
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))
        seedTestQueueStore()

        KlaviyoOrchestration.setPushToken("pre-tok", .authorized)

        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let hasToken = snap.contains {
            if case .pushToken = $0 { return true }
            return false
        }
        XCTAssertTrue(hasToken,
                      "pre-init setPushToken with no apiKey must buffer in UnattributedBuffer")
    }

    // MARK: - setAutomaticPushToken

    /// setAutomaticPushToken must forward to setPushToken with identical semantics.
    @MainActor
    func testSetAutomaticPushTokenForwardsToPushToken() {
        let (apiKey, _, _) = seedPostInitWithToken()
        IdentityStore.shared.updatePushToken(nil) // ensure no dedup
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setAutomaticPushToken("auto-tok", .authorized)

        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, "auto-tok",
                       "setAutomaticPushToken must persist the token")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case let .registerPushToken(queuedApiKey, _) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken from setAutomaticPushToken")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
    }

    // MARK: - setPushEnablement

    /// setPushEnablement re-dispatches to setPushToken via the canonical token.
    @MainActor
    func testSetPushEnablementRedispatchesToSetPushToken() {
        let (apiKey, anonymousId, pushTok) = seedPostInitWithToken()
        // Store with .denied so the new enablement (.authorized) triggers a request.
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushTok,
            pushEnablement: .denied,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPushEnablement(.authorized)

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "setPushEnablement must enqueue exactly one token request")
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken from setPushEnablement")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushTok,
                       "setPushEnablement must forward the canonical token, not a stale copy")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
    }

    /// setPushEnablement with no token → no-op.
    @MainActor
    func testSetPushEnablementNoTokenIsNoOp() {
        seedPostInitWithToken()
        IdentityStore.shared.updatePushToken(nil) // clear token
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPushEnablement(.authorized)

        XCTAssertTrue(readQueue().isEmpty,
                      "setPushEnablement with no token must not enqueue")
    }

    // MARK: - enqueueProfile: no-op (unchanged identifiers + no extra attrs)

    /// Identical profile with no extra attributes → must not enqueue anything.
    @MainActor
    func testEnqueueProfileUnchangedIdentifiersAndNoExtraAttrsIsNoOp() {
        let _ = seedPostInitWithToken(email: "same@x.com")
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(Profile(email: "same@x.com"))

        XCTAssertTrue(readQueue().isEmpty,
                      "enqueueProfile with unchanged identifiers and no extra attrs must not enqueue")
    }

    // MARK: - enqueueProfile: unchanged identifiers but has extra attrs → createProfile, no reset

    /// Same identifiers but the profile carries a firstName → must enqueue a createProfile without
    /// resetting the anonymousId.
    @MainActor
    func testEnqueueProfileUnchangedIdentifiersWithAttrsEnqueuesCreateProfile() {
        let anonBefore = "anon-stable"
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "same@x.com", anonymousId: anonBefore))
        IdentityStore.shared.updatePushToken(nil) // no token → only a createProfile
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(Profile(email: "same@x.com", firstName: "Alice"))

        XCTAssertEqual(IdentityStore.shared.current.anonymousId, anonBefore,
                       "unchanged identifiers must NOT mint a new anonymousId")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "same identifiers + extra attrs must enqueue exactly one createProfile")
        guard case .createProfile = queued.first?.endpoint else {
            return XCTFail("expected createProfile, got \(queued.first?.endpoint as Any)")
        }
    }

    // MARK: - enqueueProfile: identifier change → mint new anon + createProfile + token re-register

    /// Identifier change on an already-identified profile: mints fresh anon, clears PII,
    /// enqueues createProfile followed by a separate registerPushToken (FIFO order).
    @MainActor
    func testEnqueueProfileChangedIdentifiersMintsAnonAndEnqueuesBothRequests() {
        let tokenData = defaultTokenData
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(
            email: "old@x.com", phoneNumber: "+10000000000", externalId: "old-ext",
            anonymousId: "anon-old"
        ))
        IdentityStore.shared.updatePushToken(tokenData)
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(
            Profile(email: "new@x.com", phoneNumber: "+19999999999", externalId: "new-ext")
        )

        // Fresh anonymousId minted.
        let newAnon = IdentityStore.shared.current.anonymousId
        XCTAssertNotNil(newAnon, "enqueueProfile must not leave anonymousId nil after reset")
        XCTAssertNotEqual(newAnon, "anon-old",
                          "identifier change must mint a fresh anonymousId")

        // Two requests: createProfile first, then registerPushToken.
        let queued = readQueue()
        XCTAssertEqual(queued.count, 2,
                       "identifier change must enqueue createProfile + registerPushToken")

        guard case .createProfile = queued[0].endpoint else {
            return XCTFail("first request must be createProfile, got \(queued[0].endpoint)")
        }
        guard case .registerPushToken = queued[1].endpoint else {
            return XCTFail("second request must be registerPushToken, got \(queued[1].endpoint)")
        }
    }

    /// Identifier change must also clear staged ProfilePropertyBuffer entries (mirrors reset()).
    @MainActor
    func testEnqueueProfileChangedIdentifiersClearsStagedProperties() {
        let tokenData = defaultTokenData
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(tokenData)
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Bob"))
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(Profile(email: "new@x.com"))

        // Flush the buffer: because reset cleared the staged property, no additional request added.
        let countAfterEnqueue = readQueue().count
        let expect = XCTestExpectation(description: "flush completes")
        Task {
            await ProfilePropertyBuffer.shared.flushIntoQueue()
            expect.fulfill()
        }
        wait(for: [expect], timeout: 2)

        XCTAssertEqual(readQueue().count, countAfterEnqueue,
                       "buffer flush after identifier-change enqueueProfile must add no request — staged props cleared")
    }

    /// Token is preserved after identifier-change reset: IdentityStore.pushToken must not be nil.
    @MainActor
    func testEnqueueProfileChangedIdentifiersPreservesCanonicalPushToken() {
        let tokenData = defaultTokenData
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(tokenData)
        seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(Profile(email: "new@x.com"))

        XCTAssertNotNil(IdentityStore.shared.pushToken,
                        "identifier-change enqueueProfile must not clear the canonical push token")
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, tokenData.pushToken)
    }

    // MARK: - enqueueProfile: no push token → createProfile only

    /// No push token: identifier change must enqueue createProfile only (no registerPushToken).
    @MainActor
    func testEnqueueProfileChangedIdentifiersNoTokenEnqueuesProfileOnly() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(nil)
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(Profile(email: "new@x.com"))

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "no token → only createProfile enqueued")
        guard case .createProfile = queued.first?.endpoint else {
            return XCTFail("expected createProfile, got \(queued.first?.endpoint as Any)")
        }
    }

    // MARK: - enqueueProfile: pre-init routes to RequestEnqueuer

    /// Pre-init profile → buffered in UnattributedBuffer (RequestEnqueuer ungated path).
    @MainActor
    func testEnqueueProfilePreInitBuffersInUnattributedBuffer() {
        UnattributedBuffer.shared.reset()
        // No LifecycleState advance, no apiKey in SDKConfigStore.
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))

        KlaviyoOrchestration.enqueueProfile(Profile(email: "buf@x.com"))

        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let profiles: [CreateProfilePayload] = snap.compactMap {
            if case let .profile(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(profiles.count, 1, "pre-init enqueueProfile must buffer a profile")
        XCTAssertEqual(profiles.first?.data.attributes.email, "buf@x.com")
    }

    /// Pre-init identifier change → mint fresh anon AND buffer the profile.
    @MainActor
    func testEnqueueProfilePreInitChangedIdentifiersMintsAnonAndBuffers() {
        UnattributedBuffer.shared.reset()
        let previousAnon = "prev-anon"
        IdentityStore.shared.update(ProfileData(email: "old@user.com", anonymousId: previousAnon))

        KlaviyoOrchestration.enqueueProfile(Profile(email: "new@user.com"))

        XCTAssertNotEqual(IdentityStore.shared.current.anonymousId, previousAnon,
                          "pre-init identifier change must mint a new anonymousId")
        XCTAssertEqual(IdentityStore.shared.current.email, "new@user.com")
        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        XCTAssertEqual(snap.count, 1, "pre-init identifier change must buffer a profile")
    }

    // MARK: - enqueueProfile: whitespace trimming

    /// Trailing whitespace on identifiers must be trimmed before comparison and enqueueing.
    @MainActor
    func testEnqueueProfileTrimsWhitespaceOnIdentifiers() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-ws"))
        IdentityStore.shared.updatePushToken(nil)
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(
            Profile(email: "trim@x.com ", phoneNumber: "+10000000000   ", externalId: "ext  ")
        )

        XCTAssertEqual(IdentityStore.shared.current.email, "trim@x.com",
                       "email must be trimmed")
        XCTAssertEqual(IdentityStore.shared.current.phoneNumber, "+10000000000",
                       "phone number must be trimmed")
        XCTAssertEqual(IdentityStore.shared.current.externalId, "ext",
                       "externalId must be trimmed")

        let queued = readQueue()
        XCTAssertFalse(queued.isEmpty, "trimmed identifiers are new → must enqueue")
        guard case let .createProfile(_, payload) = queued.first?.endpoint else {
            return XCTFail("expected createProfile")
        }
        XCTAssertEqual(payload.data.attributes.email, "trim@x.com")
        XCTAssertEqual(payload.data.attributes.phoneNumber, "+10000000000")
        XCTAssertEqual(payload.data.attributes.externalId, "ext")
    }

    // MARK: - enqueueSubscription

    /// Happy path: anonymousId present + valid email → enqueues a createSubscription.
    @MainActor
    func testEnqueueSubscriptionHappyPath() {
        let (apiKey, anonymousId, _) = seedPostInitWithToken(email: "sub@x.com")
        let readQueue = seedTestQueueStore()

        let subscription = Subscription.allAvailableMarketing(listId: "list-abc")
        KlaviyoOrchestration.enqueueSubscription(subscription)

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "valid subscription must enqueue exactly one request")
        guard case let .createSubscription(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected createSubscription, got \(queued.first?.endpoint as Any)")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.relationships.list.data.id, "list-abc")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.email, "sub@x.com")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
    }

    /// No anonymousId → guard fires, nothing enqueued.
    @MainActor
    func testEnqueueSubscriptionNoAnonymousIdIsNoOp() {
        // IdentityStore starts with no anonymousId after reset().
        IdentityStore.shared.update(ProfileData()) // anonymousId nil
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueSubscription(
            Subscription.allAvailableMarketing(listId: "list-xyz")
        )

        XCTAssertTrue(readQueue().isEmpty,
                      "enqueueSubscription with no anonymousId must not enqueue")
    }

    /// allAvailableMarketing with no email/phone → developer warning, no enqueue.
    @MainActor
    func testEnqueueSubscriptionMissingIdentifiersDoesNotEnqueue() {
        var warningFired = false
        environment.emitDeveloperWarning = { _ in warningFired = true }

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-sub")) // no email/phone
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueSubscription(
            Subscription.allAvailableMarketing(listId: "list-noident")
        )

        XCTAssertTrue(warningFired, "missing identifiers must emit a developer warning")
        XCTAssertTrue(readQueue().isEmpty,
                      "missing identifiers must not enqueue a subscription")
    }

    /// Subscription with explicit channels (email marketing) → enqueues with correct channel mapping.
    @MainActor
    func testEnqueueSubscriptionWithChannelsEnqueues() {
        let (apiKey, anonymousId, _) = seedPostInitWithToken(email: "ch@x.com")
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueSubscription(
            Subscription(listId: "list-ch", channels: .init(email: .marketing))
        )

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case let .createSubscription(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected createSubscription")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
        XCTAssertNotNil(payload.data.attributes.profile.data.attributes.subscriptions,
                        "channels must be present in the payload")
    }

    // MARK: - enqueueProfile: FIFO ordering (profile ahead of token re-register)

    /// Two requests enqueued in order: createProfile at index 0, registerPushToken at index 1.
    @MainActor
    func testEnqueueProfileTokenReregisterIsAfterCreateProfile() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-order"))
        IdentityStore.shared.updatePushToken(defaultTokenData)
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueProfile(Profile(email: "new@x.com"))

        let queued = readQueue()
        XCTAssertEqual(queued.count, 2)
        if case .createProfile = queued[0].endpoint {} else {
            XCTFail("createProfile must be first (FIFO order)")
        }
        if case .registerPushToken = queued[1].endpoint {} else {
            XCTFail("registerPushToken must be second (FIFO order)")
        }
    }
}
