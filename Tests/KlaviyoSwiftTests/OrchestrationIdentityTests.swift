//
//  OrchestrationIdentityTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/14/26.
//
//  Parity coverage for the identity-setter reducer cases (`setEmail`, `setPhoneNumber`,
//  `setExternalId`, `resetProfile`, `setProfileProperty`) that are being ported into
//  `KlaviyoOrchestration`. These tests exercise the NEW orchestration functions directly,
//  reproducing the coverage that will be removed from `StateManagementTests` /
//  `StateManagementEdgeCaseTests` when those files are deleted in a later task.

@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
import Foundation
import XCTest

class OrchestrationIdentityTests: StateManagementTestCase {
    // MARK: - Test lifecycle

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        // LifecycleState is a KlaviyoSwift singleton, not reset by `resetCanonicalCoreStores`.
        // Reset it so each test starts from a known `.uninitialized` baseline.
        LifecycleState.shared.reset()
    }

    // MARK: - Helpers

    /// Seeds the canonical stores for a post-init state with a push token.
    ///
    /// Also advances `LifecycleState` to `.initialized` so `applyIdentifierChange`'s
    /// `LifecycleState.shared.current != .uninitialized` gate fires (matching the old reducer's
    /// `state.apiKey != nil` gate — both are true only after this session's `initialize()` runs).
    ///
    /// Returns the apiKey, anonymousId, and pushToken seeded.
    @discardableResult
    private func seedPostInitWithToken(
        apiKey: String = TEST_API_KEY,
        anonymousId: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil
    ) -> (apiKey: String, anonymousId: String, pushToken: String) {
        let resolvedAnonymousId = anonymousId ?? environment.uuid().uuidString
        let pushToken = "blob_token"
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(ProfileData(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: resolvedAnonymousId
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushToken,
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        // Advance lifecycle so the post-init gate matches the old `state.apiKey != nil` condition.
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()
        return (apiKey, resolvedAnonymousId, pushToken)
    }

    /// Seeds the canonical stores for a pre-init state (no apiKey, identity has anonymousId).
    /// `LifecycleState` remains `.uninitialized` (the default after `setUp`).
    private func seedPreInit(anonymousId: String? = nil) {
        let resolvedAnonymousId = anonymousId ?? environment.uuid().uuidString
        IdentityStore.shared.update(ProfileData(anonymousId: resolvedAnonymousId))
    }

    // MARK: - setEmail

    /// Post-init + token present: a new email must persist to IdentityStore and enqueue a token
    /// re-association request via QueueStore.
    @MainActor
    func testSetEmailPostInitWithTokenReassociatesViaQueueStore() {
        let (apiKey, anonymousId, pushToken) = seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setEmail("new@x.com")

        XCTAssertEqual(IdentityStore.shared.current.email, "new@x.com",
                       "setEmail must persist the new email to IdentityStore")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "setEmail post-init+token must enqueue exactly one token request")

        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken, got \(queued.first?.endpoint as Any)")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushToken)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.email, "new@x.com")
    }

    /// Pre-init (no apiKey): new email must persist and fall through to RequestEnqueuer, buffering
    /// a createProfile payload in the UnattributedBuffer.
    @MainActor
    func testSetEmailPreInitEnqueuesProfileViaRequestEnqueuerBuffer() {
        UnattributedBuffer.shared.reset()
        seedPreInit()

        KlaviyoOrchestration.setEmail("buffered@x.com")

        XCTAssertEqual(IdentityStore.shared.current.email, "buffered@x.com")
        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let profiles: [CreateProfilePayload] = snap.compactMap {
            if case let .profile(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(profiles.count, 1,
                       "pre-init setEmail must buffer a profile via RequestEnqueuer")
        XCTAssertEqual(profiles.first?.data.attributes.email, "buffered@x.com")
    }

    /// Empty string: must be a no-op — no store write, no enqueue.
    @MainActor
    func testSetEmailEmptyStringIsNoOp() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()
        let beforeEmail = IdentityStore.shared.current.email

        KlaviyoOrchestration.setEmail("")

        XCTAssertEqual(IdentityStore.shared.current.email, beforeEmail,
                       "setEmail with empty string must not change identity")
        XCTAssertTrue(readQueue().isEmpty, "setEmail with empty string must not enqueue")
    }

    /// Same value: must be a no-op — no store write, no enqueue.
    @MainActor
    func testSetEmailSameValueIsNoOp() {
        seedPostInitWithToken(email: "same@example.com")
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setEmail("same@example.com")

        XCTAssertTrue(readQueue().isEmpty, "setEmail with unchanged value must not enqueue")
    }

    // MARK: - setPhoneNumber

    /// Post-init + token: new phone must persist and enqueue a token re-association.
    @MainActor
    func testSetPhoneNumberPostInitWithTokenReassociatesViaQueueStore() {
        let (apiKey, anonymousId, pushToken) = seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPhoneNumber("+18005551234")

        XCTAssertEqual(IdentityStore.shared.current.phoneNumber, "+18005551234")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushToken)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.phoneNumber, "+18005551234")
    }

    /// Pre-init: new phone must buffer a profile.
    @MainActor
    func testSetPhoneNumberPreInitEnqueuesProfileBuffer() {
        UnattributedBuffer.shared.reset()
        seedPreInit()

        KlaviyoOrchestration.setPhoneNumber("+18005559999")

        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let profiles: [CreateProfilePayload] = snap.compactMap {
            if case let .profile(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.data.attributes.phoneNumber, "+18005559999")
    }

    /// Empty string is a no-op.
    @MainActor
    func testSetPhoneNumberEmptyStringIsNoOp() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPhoneNumber("")

        XCTAssertNil(IdentityStore.shared.current.phoneNumber)
        XCTAssertTrue(readQueue().isEmpty)
    }

    /// Same value is a no-op.
    @MainActor
    func testSetPhoneNumberSameValueIsNoOp() {
        seedPostInitWithToken(phoneNumber: "+18005551234")
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setPhoneNumber("+18005551234")

        XCTAssertTrue(readQueue().isEmpty)
    }

    // MARK: - setExternalId

    /// Post-init + token: new externalId must persist and enqueue a token re-association.
    @MainActor
    func testSetExternalIdPostInitWithTokenReassociatesViaQueueStore() {
        let (apiKey, anonymousId, pushToken) = seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setExternalId("ext-42")

        XCTAssertEqual(IdentityStore.shared.current.externalId, "ext-42")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushToken)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.anonymousId, anonymousId)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.externalId, "ext-42")
    }

    /// Pre-init: new externalId must buffer a profile.
    @MainActor
    func testSetExternalIdPreInitEnqueuesProfileBuffer() {
        UnattributedBuffer.shared.reset()
        seedPreInit()

        KlaviyoOrchestration.setExternalId("pre-init-ext")

        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let profiles: [CreateProfilePayload] = snap.compactMap {
            if case let .profile(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.data.attributes.externalId, "pre-init-ext")
    }

    /// Empty string is a no-op.
    @MainActor
    func testSetExternalIdEmptyStringIsNoOp() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setExternalId("")

        XCTAssertNil(IdentityStore.shared.current.externalId)
        XCTAssertTrue(readQueue().isEmpty)
    }

    /// Same value is a no-op.
    @MainActor
    func testSetExternalIdSameValueIsNoOp() {
        seedPostInitWithToken(externalId: "user-42")
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setExternalId("user-42")

        XCTAssertTrue(readQueue().isEmpty)
    }

    // MARK: - resetProfile

    /// After resetProfile, email is cleared, anonymousId is fresh, push token is preserved in
    /// IdentityStore, and a token re-registration request is enqueued.
    @MainActor
    func testResetProfileMintsAnonClearsIdentityAndReregistersToken() {
        let anonBefore = "anon-before"
        let (apiKey, _, pushToken) = seedPostInitWithToken(
            anonymousId: anonBefore, email: "old@x.com"
        )
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.resetProfile()

        XCTAssertNil(IdentityStore.shared.current.email, "resetProfile must clear email")
        XCTAssertNil(IdentityStore.shared.current.phoneNumber, "resetProfile must clear phone")
        XCTAssertNil(IdentityStore.shared.current.externalId, "resetProfile must clear externalId")
        XCTAssertNotNil(IdentityStore.shared.current.anonymousId,
                        "resetProfile must leave a fresh anonymousId")
        XCTAssertNotEqual(IdentityStore.shared.current.anonymousId, anonBefore,
                          "resetProfile of identified profile must mint a new anonymousId")
        // Token must be preserved (not cleared from IdentityStore).
        XCTAssertNotNil(IdentityStore.shared.pushToken,
                        "resetProfile must preserve the canonical push token")
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, pushToken)

        // Exactly one token re-register, under the fresh anonymousId.
        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "resetProfile enqueues exactly one token re-register")
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken after resetProfile")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushToken)
        XCTAssertEqual(
            payload.data.attributes.profile.data.attributes.anonymousId,
            IdentityStore.shared.current.anonymousId,
            "token re-register must use the post-reset (fresh) anonymousId"
        )
    }

    /// resetProfile with no token must not enqueue anything.
    @MainActor
    func testResetProfileWithNoTokenEnqueuesNothing() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(email: "old@x.com", anonymousId: "anon-old"))
        // No push token.
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.resetProfile()

        XCTAssertNil(IdentityStore.shared.current.email)
        XCTAssertTrue(readQueue().isEmpty, "resetProfile with no token must enqueue nothing")
    }

    /// resetProfile must also clear staged ProfilePropertyBuffer entries.
    @MainActor
    func testResetProfileClearsStagedProfileProperties() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Bob"))

        KlaviyoOrchestration.resetProfile()

        // resetProfile enqueues exactly one token re-registration request.
        let countAfterReset = readQueue().count
        XCTAssertEqual(countAfterReset, 1, "resetProfile must enqueue exactly one token re-register")

        // Flush the buffer (simulating willDrain). Because reset cleared the staged property,
        // the flush must not enqueue any additional request.
        let expect = XCTestExpectation(description: "flush completes")
        Task {
            await ProfilePropertyBuffer.shared.flushIntoQueue()
            expect.fulfill()
        }
        wait(for: [expect], timeout: 2)

        XCTAssertEqual(readQueue().count, countAfterReset,
                       "buffer flush after resetProfile must not add any request — staged props were cleared")
    }

    /// resetProfile on an already-anonymous profile (no email/phone/externalId) must NOT mint a
    /// fresh anonymousId — the existing anonymousId must be preserved.
    ///
    /// Parity: `KlaviyoState.reset` only calls `environment.uuid()` when `isIdentified` is true.
    @MainActor
    func testResetProfileOnAnonymousProfilePreservesAnonymousId() {
        let anonId = "anon-already-anonymous"
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: anonId)) // no email/phone/externalId

        KlaviyoOrchestration.resetProfile()

        XCTAssertEqual(IdentityStore.shared.current.anonymousId, anonId,
                       "resetProfile on an anonymous profile must preserve anonymousId")
    }

    // MARK: - setProfileProperty

    /// setProfileProperty stages the key/value into ProfilePropertyBuffer; it does NOT enqueue.
    @MainActor
    func testSetProfilePropertyStagesIntoBufferNoEnqueue() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setProfileProperty(.firstName, AnyEncodable("Alice"))

        XCTAssertTrue(readQueue().isEmpty,
                      "setProfileProperty must not enqueue directly — staging only")
    }

    /// setProfileProperty: staged values fold into a request on the next buffer flush.
    @MainActor
    func testSetProfilePropertyStagedValueAppearsOnFlush() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setProfileProperty(.firstName, AnyEncodable("Alice"))

        let flushExpect = XCTestExpectation(description: "flush")
        Task {
            await ProfilePropertyBuffer.shared.flushIntoQueue()
            flushExpect.fulfill()
        }
        wait(for: [flushExpect], timeout: 2)

        guard let request = readQueue().first else {
            return XCTFail("expected a request after buffer flush")
        }
        switch request.endpoint {
        case let .registerPushToken(_, payload):
            XCTAssertEqual(payload.data.attributes.profile.data.attributes.firstName, "Alice")
        default:
            XCTFail("expected registerPushToken from buffer flush")
        }
    }

    // MARK: - R4 Regression: 4xx field-clear must not be resurrected by a subsequent setter

    /// Plan self-review R4: if a `RequestQueue` 4xx handler clears an identifier directly on
    /// `IdentityStore` (e.g. clears email due to an invalid-email error), a subsequent `setEmail`
    /// call must NOT resurrect the old cleared value. Because there is no longer a `KlaviyoState`
    /// projection that can re-persist the stale value, the cleared field must stay gone and only the
    /// new value from the setter call must appear.
    @MainActor
    func testSetEmailAfter4xxFieldClearDoesNotResurrectClearedIdentifier() {
        // Arrange: start with a post-init state that has an email.
        seedPostInitWithToken(email: "stale@x.com")
        let readQueue = seedTestQueueStore()

        // Simulate a 4xx field-clear: the RequestQueue handler clears the email directly on
        // IdentityStore (the canonical store). There is no longer a KlaviyoState projection
        // that could re-persist "stale@x.com", so the clear is durable.
        IdentityStore.shared.mutate { $0.email = nil }

        XCTAssertNil(IdentityStore.shared.current.email, "sanity: 4xx clear must take effect")

        // Act: call setEmail with a fresh value.
        KlaviyoOrchestration.setEmail("fresh@x.com")

        // Assert: only the fresh email is present — "stale@x.com" was not resurrected.
        XCTAssertEqual(IdentityStore.shared.current.email, "fresh@x.com",
                       "new email must be set")

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1)
        guard case let .registerPushToken(_, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken after setEmail")
        }
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.email, "fresh@x.com",
                       "token re-association must carry the NEW email, not the cleared stale one")
        XCTAssertNil(
            // No externalId or phone — only the email set by the fresh call.
            payload.data.attributes.profile.data.attributes.externalId,
            "stale email must not be resurrected in the request payload"
        )
    }

    // MARK: - Pre-init setter with stored token: falls through to profile branch

    /// Regression gate: pre-init setEmail with a token stored in IdentityStore must buffer a
    /// profile (not drop silently), matching the reducer's `applyIdentifierChange` gate on
    /// `state.apiKey`.
    @MainActor
    func testSetEmailPreInitWithStoredTokenBuffersProfile() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // No apiKey in SDKConfigStore (pre-init).
        IdentityStore.shared.update(ProfileData(
            email: "old@example.com", externalId: "user-A", anonymousId: "anon-A"
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "tok-preInit",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))

        KlaviyoOrchestration.setEmail("new@example.com")

        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        let profiles: [CreateProfilePayload] = snap.compactMap {
            if case let .profile(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(profiles.count, 1,
                       "pre-init setEmail with a stored token must buffer a profile, not drop")
        XCTAssertEqual(profiles.first?.data.attributes.email, "new@example.com")
    }

    /// Warm-start before initialize: `SDKConfigStore` has a persisted apiKey from a prior launch,
    /// a push token is stored in `IdentityStore`, but `initialize()` has NOT been called this
    /// session — so `LifecycleState.shared.current == .uninitialized`.
    ///
    /// PARITY with old reducer: `state.apiKey` was nil until the `.initializing` transition, so the
    /// old reducer fell through to `RequestEnqueuer.enqueueProfile` (profile branch), not the token
    /// re-association branch. The new orchestration must reproduce this behavior by gating on
    /// `LifecycleState`, not on `SDKConfigStore`.
    ///
    /// Expected: `setEmail` buffers a **profile** via `RequestEnqueuer` (lands in `UnattributedBuffer`
    /// when `SDKConfigStore` has no apiKey, or routes to `QueueStore` when it does — either way NOT
    /// a token re-association). QueueStore must be empty (no registerPushToken enqueued).
    @MainActor
    func testSetEmailWarmStartPreInitBuffersProfileNotTokenReassociation() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        // LifecycleState is .uninitialized (reset in setUp + not advanced here — warm start).
        XCTAssertEqual(LifecycleState.shared.current, .uninitialized,
                       "precondition: warm-start must start with LifecycleState == .uninitialized")
        // Warm start: apiKey already persisted in SDKConfigStore from a prior launch.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "persisted-key"))
        let anonId = "anon-A"
        IdentityStore.shared.update(ProfileData(
            email: "old@example.com", externalId: "user-A", anonymousId: anonId
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "tok-warmStart",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setEmail("new@example.com")

        // PARITY: warm-start (LifecycleState == .uninitialized) must take the PROFILE branch,
        // exactly as the old reducer did when state.apiKey was nil.
        // The enqueued request must be a createProfile, NOT a registerPushToken.
        // (RequestEnqueuer re-gates on SDKConfigStore: since "persisted-key" is present, the
        // profile lands directly in QueueStore — consistent with old warm-start behavior.)
        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "warm-start setEmail must enqueue exactly one request")
        guard case .createProfile = queued.first?.endpoint else {
            return XCTFail(
                "warm-start setEmail must enqueue a createProfile (not registerPushToken), "
                    + "got \(queued.first?.endpoint as Any)"
            )
        }
        // Identity update must still be persisted.
        XCTAssertEqual(IdentityStore.shared.current.email, "new@example.com",
                       "warm-start setEmail must persist the new email to IdentityStore")
    }

    /// Post-init (LifecycleState == .initialized) + token present: setEmail must enqueue a TOKEN
    /// re-association, NOT a profile. This is the parity boundary opposite to the warm-start case.
    @MainActor
    func testSetEmailPostInitWithTokenEnqueuesTokenReassociationNotProfile() {
        UnattributedBuffer.shared.reset()
        let (apiKey, _, pushToken) = seedPostInitWithToken() // advances LifecycleState to .initialized
        XCTAssertNotEqual(LifecycleState.shared.current, .uninitialized,
                          "precondition: post-init must have LifecycleState != .uninitialized")
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.setEmail("parity@x.com")

        // Profile branch must NOT have fired.
        let snap = UnattributedBuffer.shared.drainSnapshot().requests
        XCTAssertTrue(snap.isEmpty, "post-init setEmail must NOT buffer a profile via UnattributedBuffer")

        // Token branch must have fired.
        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "post-init+token setEmail must enqueue exactly one request")
        guard case let .registerPushToken(queuedApiKey, payload) = queued.first?.endpoint else {
            return XCTFail("expected registerPushToken, got \(queued.first?.endpoint as Any)")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
        XCTAssertEqual(payload.data.attributes.token, pushToken)
        XCTAssertEqual(payload.data.attributes.profile.data.attributes.email, "parity@x.com",
                       "token re-association must carry the updated email")
    }
}
