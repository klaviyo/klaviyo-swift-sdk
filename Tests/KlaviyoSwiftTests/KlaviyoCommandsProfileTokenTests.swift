//
//  KlaviyoCommandsProfileTokenTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/14/26.
//
//  Coverage for the push-token, profile, and subscription orchestration functions in
//  `KlaviyoCommands`.

@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
import Foundation
import XCTest

class KlaviyoCommandsProfileTokenTests: KlaviyoBaseTestCase {
    // MARK: - Test lifecycle

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        // LifecycleState is a KlaviyoSwift singleton; reset so each test starts `.uninitialized`.
        LifecycleState.shared.reset()
    }

    // MARK: - Helpers

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

        KlaviyoCommands.setPushToken(tokenData.pushToken, tokenData.pushEnablement)

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

        KlaviyoCommands.setPushToken("new-tok", .authorized)

        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, "new-tok",
                       "post-init token must be persisted as it is routed to QueueStore")

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

        KlaviyoCommands.setPushToken(pushTok, .authorized)

        XCTAssertEqual(IdentityStore.shared.pushToken?.pushEnablement, .authorized,
                       "updated enablement must be persisted as the token is routed")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushTok)
        XCTAssertEqual(payload.data.attributes.enablementStatus, PushEnablement.authorized.rawValue,
                       "enqueued request must carry the new enablement")
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
    }

    /// Rotation then enablement change: `setPushToken(B)` persists B immediately (as it is routed),
    /// so a following `setPushEnablement` re-registers B — never the stale prior token. Guards the
    /// pending-vs-registered token window (CR-2 / consequence #1).
    @MainActor
    func testTokenRotationThenEnablementTargetsNewToken() {
        seedPostInitWithToken(pushToken: "tok-A")
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setPushToken("tok-B", .authorized) // rotation → persists B
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, "tok-B",
                       "rotation must persist the new token immediately")

        KlaviyoCommands.setPushEnablement(.denied) // reads canonical token → B, not stale A

        let tokens: [String] = readQueue().compactMap {
            if case let .registerPushToken(_, payload) = $0.endpoint { return payload.data.attributes.token }
            return nil
        }
        XCTAssertEqual(tokens, ["tok-B", "tok-B"],
                       "rotation + enablement must both target the new token, never the stale one")
    }

    // MARK: - setPushToken: warm-start (LifecycleState == .uninitialized)

    /// Warm-start parity: SDKConfigStore has a persisted apiKey but initialize() has NOT run this
    /// session (SessionState == false). Under default parity flags a pre-init token is dropped — NOT
    /// stamped under the disk-hydrated apiKey — matching how both released SDKs defer/drop pre-init.
    @MainActor
    func testSetPushTokenWarmStartPreInitDroppedUnderParity() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        PreInitMemoryBuffer.shared.reset()
        // LifecycleState stays .uninitialized (reset in setUp, not advanced here).
        XCTAssertEqual(LifecycleState.shared.current, .uninitialized,
                       "precondition: warm-start requires LifecycleState == .uninitialized")
        // Persisted apiKey from a prior launch, but initialize() has not run this session.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-warm"))
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setPushToken("warm-tok", .authorized)

        XCTAssertTrue(readQueue().isEmpty,
                      "warm-start pre-init token must NOT be stamped under the persisted apiKey")
        XCTAssertNil(IdentityStore.shared.pushToken,
                     "dropped token must not be persisted")
    }

    /// Pre-init (no apiKey anywhere) → token ends up in UnattributedBuffer.
    @MainActor
    func testSetPushTokenPreInitNoApiKeyBuffersInUnattributedBuffer() {
        featureFlags.enablePreInitDiskCapture = true
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // LifecycleState stays .uninitialized, SDKConfigStore has NO apiKey.
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))
        seedTestQueueStore()

        KlaviyoCommands.setPushToken("pre-tok", .authorized)

        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let hasToken = snap.contains {
            if case .pushToken = $0 { return true }
            return false
        }
        XCTAssertTrue(hasToken,
                      "pre-init setPushToken with no apiKey must buffer in UnattributedBuffer")
    }

    /// Regression (default parity flags): a pre-init `setPushToken` is dropped WITHOUT persisting to
    /// `IdentityStore`, so the identical token after init is not deduped out and registers. Guards
    /// against the "pre-init token never registers" bug.
    @MainActor
    func testSetPushTokenPreInitDropThenPostInitRegisters() {
        // Default parity: enablePreInitDiskCapture == false (base setUp resets featureFlags).
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        PreInitMemoryBuffer.shared.reset()
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))
        let readQueue = seedTestQueueStore()

        // Pre-init (LifecycleState .uninitialized, no apiKey): the token request is dropped and,
        // critically, NOT persisted — so the dedup can't later swallow the same token.
        KlaviyoCommands.setPushToken("tok-A", .authorized)
        XCTAssertNil(IdentityStore.shared.pushToken,
                     "pre-init dropped token must not be persisted")
        XCTAssertTrue(readQueue().isEmpty,
                      "pre-init token must not reach QueueStore under default parity flags")

        // Simulate initialize(): apiKey known + LifecycleState advanced.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()

        // The SAME token, now post-init, must register (not dedup out against a stale disk copy).
        KlaviyoCommands.setPushToken("tok-A", .authorized)

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "post-init setPushToken must register after a pre-init drop of the same token")
        guard case .registerPushToken = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken, got \(queued.first?.endpoint as Any)")
        }
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

        KlaviyoCommands.setPushEnablement(.authorized)

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

        KlaviyoCommands.setPushEnablement(.authorized)

        XCTAssertTrue(readQueue().isEmpty,
                      "setPushEnablement with no token must not enqueue")
    }

    // MARK: - enqueueProfile: no-op (unchanged identifiers + no extra attrs)

    /// Identical profile with no extra attributes → must not enqueue anything.
    @MainActor
    func testEnqueueProfileUnchangedIdentifiersAndNoExtraAttrsIsNoOp() {
        _ = seedPostInitWithToken(email: "same@x.com")
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(email: "same@x.com"))

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
        markSessionInitialized()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(email: "same@x.com", firstName: "Alice"))

        XCTAssertEqual(IdentityStore.shared.current.anonymousId, anonBefore,
                       "unchanged identifiers must NOT mint a new anonymousId")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "same identifiers + extra attrs must enqueue exactly one createProfile")
        guard case .createProfile = queued.first?.endpoint else {
            return XCTFail("expected createProfile, got \(queued.first?.endpoint as Any)")
        }
    }

    // MARK: - enqueueProfile: identifier change → mint new anon + clear staged props

    /// Identifier change must also clear staged ProfilePropertyBuffer entries (mirrors reset()).
    @MainActor
    func testEnqueueProfileChangedIdentifiersClearsStagedProperties() {
        let tokenData = defaultTokenData
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(tokenData)
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Bob"))
        markSessionInitialized()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(email: "new@x.com"))

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

        KlaviyoCommands.enqueueProfile(Profile(email: "new@x.com"))

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
        markSessionInitialized()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(email: "new@x.com"))

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
        featureFlags.enablePreInitDiskCapture = true
        UnattributedBuffer.shared.reset()
        // No LifecycleState advance, no apiKey in SDKConfigStore.
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))

        KlaviyoCommands.enqueueProfile(Profile(email: "buf@x.com"))

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
        featureFlags.enablePreInitDiskCapture = true
        UnattributedBuffer.shared.reset()
        let previousAnon = "prev-anon"
        IdentityStore.shared.update(ProfileData(email: "old@user.com", anonymousId: previousAnon))

        KlaviyoCommands.enqueueProfile(Profile(email: "new@user.com"))

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
        markSessionInitialized()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(
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
        KlaviyoCommands.enqueueSubscription(subscription)

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

        KlaviyoCommands.enqueueSubscription(
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

        KlaviyoCommands.enqueueSubscription(
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

        KlaviyoCommands.enqueueSubscription(
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

    // MARK: - enqueueProfile: fold profile + token into one request

    /// Identifier change WITH a token → ONE registerPushToken carrying the full (new) identity and a
    /// freshly-minted anon, NO createProfile.
    @MainActor
    func testChangedIdentifiersWithTokenEnqueuesSingleFoldedToken() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(defaultTokenData)
        markSessionInitialized()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(email: "new@x.com", firstName: "Alice"))

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "fold: exactly one request when a token exists")
        guard case let .registerPushToken(_, payload) = queued.first?.endpoint else {
            return XCTFail("fold: expected registerPushToken, got \(queued.first?.endpoint as Any)")
        }
        let foldedProfile = payload.data.attributes.profile.data.attributes
        XCTAssertEqual(foldedProfile.email, "new@x.com",
                       "folded token must carry the new identity")
        XCTAssertEqual(foldedProfile.firstName, "Alice",
                       "folded token must carry the profile attributes, not just identifiers")
        XCTAssertNotEqual(IdentityStore.shared.current.anonymousId, "anon-old",
                          "identifier change must mint a fresh anonymousId")
        XCTAssertEqual(foldedProfile.anonymousId, IdentityStore.shared.current.anonymousId,
                       "folded token must carry the freshly-minted anonymousId")
    }

    /// Parity: no token → createProfile only (unchanged).
    @MainActor
    func testFoldParityNoTokenEnqueuesCreateProfileOnly() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(nil)
        markSessionInitialized()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.enqueueProfile(Profile(email: "new@x.com"))

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case .createProfile = queued.first?.endpoint else {
            return XCTFail("no token → createProfile only")
        }
    }

    /// Regression (default parity): a pre-init `set(profile:)` is dropped WITHOUT persisting identity,
    /// so the same profile after `initialize()` still syncs instead of being treated as unchanged.
    @MainActor
    func testEnqueueProfilePreInitDropThenPostInitSends() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        PreInitMemoryBuffer.shared.reset()
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))
        let readQueue = seedTestQueueStore()

        // Pre-init (uninitialized, default parity): dropped, not persisted.
        KlaviyoCommands.enqueueProfile(Profile(email: "p@x.com"))
        XCTAssertNil(IdentityStore.shared.current.email, "pre-init profile must not be persisted")
        XCTAssertTrue(readQueue().isEmpty, "pre-init profile must not enqueue")

        // Simulate initialize().
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        markSessionInitialized()

        // The SAME profile post-init must now sync (not treated as unchanged).
        KlaviyoCommands.enqueueProfile(Profile(email: "p@x.com"))
        XCTAssertEqual(IdentityStore.shared.current.email, "p@x.com")
        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "post-init enqueueProfile must send after a pre-init drop of the same profile")
        guard case .createProfile = queued.first?.endpoint else {
            return XCTFail("expected createProfile, got \(queued.first?.endpoint as Any)")
        }
    }
}
