//
//  KlaviyoCommandsIdentityTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/14/26.
//
//  Coverage for the identity-setter orchestration functions (`setEmail`, `setPhoneNumber`,
//  `setExternalId`, `resetProfile`, `setProfileProperty`) in `KlaviyoCommands`.

@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
import Foundation
import XCTest

class KlaviyoCommandsIdentityTests: KlaviyoBaseTestCase {
    // MARK: - Test lifecycle

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        // LifecycleState is a KlaviyoSwift singleton, not reset by `resetCanonicalCoreStores`.
        // Reset it so each test starts from a known `.uninitialized` baseline.
        LifecycleState.shared.reset()
    }

    // MARK: - setEmail

    /// Post-init + token present: a new email must persist to IdentityStore and enqueue a token
    /// re-association request via QueueStore.
    @MainActor
    func testSetEmailPostInitWithTokenReassociatesViaQueueStore() {
        let (apiKey, anonymousId, pushToken) = seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setEmail("new@x.com")

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
        featureFlags.enablePreInitDiskCapture = true
        UnattributedBuffer.shared.reset()
        seedPreInit()

        KlaviyoCommands.setEmail("buffered@x.com")

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

        KlaviyoCommands.setEmail("")

        XCTAssertEqual(IdentityStore.shared.current.email, beforeEmail,
                       "setEmail with empty string must not change identity")
        XCTAssertTrue(readQueue().isEmpty, "setEmail with empty string must not enqueue")
    }

    /// Same value: must be a no-op — no store write, no enqueue.
    @MainActor
    func testSetEmailSameValueIsNoOp() {
        seedPostInitWithToken(email: "same@example.com")
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setEmail("same@example.com")

        XCTAssertTrue(readQueue().isEmpty, "setEmail with unchanged value must not enqueue")
    }

    // MARK: - setPhoneNumber

    /// Post-init + token: new phone must persist and enqueue a token re-association.
    @MainActor
    func testSetPhoneNumberPostInitWithTokenReassociatesViaQueueStore() {
        let (apiKey, anonymousId, pushToken) = seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setPhoneNumber("+18005551234")

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
        featureFlags.enablePreInitDiskCapture = true
        UnattributedBuffer.shared.reset()
        seedPreInit()

        KlaviyoCommands.setPhoneNumber("+18005559999")

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

        KlaviyoCommands.setPhoneNumber("")

        XCTAssertNil(IdentityStore.shared.current.phoneNumber)
        XCTAssertTrue(readQueue().isEmpty)
    }

    /// Same value is a no-op.
    @MainActor
    func testSetPhoneNumberSameValueIsNoOp() {
        seedPostInitWithToken(phoneNumber: "+18005551234")
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setPhoneNumber("+18005551234")

        XCTAssertTrue(readQueue().isEmpty)
    }

    // MARK: - setExternalId

    /// Post-init + token: new externalId must persist and enqueue a token re-association.
    @MainActor
    func testSetExternalIdPostInitWithTokenReassociatesViaQueueStore() {
        let (apiKey, anonymousId, pushToken) = seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setExternalId("ext-42")

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
        featureFlags.enablePreInitDiskCapture = true
        UnattributedBuffer.shared.reset()
        seedPreInit()

        KlaviyoCommands.setExternalId("pre-init-ext")

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

        KlaviyoCommands.setExternalId("")

        XCTAssertNil(IdentityStore.shared.current.externalId)
        XCTAssertTrue(readQueue().isEmpty)
    }

    /// Same value is a no-op.
    @MainActor
    func testSetExternalIdSameValueIsNoOp() {
        seedPostInitWithToken(externalId: "user-42")
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setExternalId("user-42")

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

        KlaviyoCommands.resetProfile()

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
        markSessionInitialized()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.resetProfile()

        XCTAssertNil(IdentityStore.shared.current.email)
        XCTAssertTrue(readQueue().isEmpty, "resetProfile with no token must enqueue nothing")
    }

    /// resetProfile must also clear staged ProfilePropertyBuffer entries.
    @MainActor
    func testResetProfileClearsStagedProfileProperties() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()
        ProfilePropertyBuffer.shared.stage(.firstName, AnyEncodable("Bob"))

        KlaviyoCommands.resetProfile()

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
    /// `IdentityStore.reset()` only calls `environment.uuid()` when `isIdentified` is true.
    @MainActor
    func testResetProfileOnAnonymousProfilePreservesAnonymousId() {
        let anonId = "anon-already-anonymous"
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: anonId)) // no email/phone/externalId
        markSessionInitialized()

        KlaviyoCommands.resetProfile()

        XCTAssertEqual(IdentityStore.shared.current.anonymousId, anonId,
                       "resetProfile on an anonymous profile must preserve anonymousId")
    }

    /// Parity: a pre-init `resetProfile` is a no-op — no identity mutation, no request. Matches
    /// Swift/Android, and avoids a warm-start reset that logs the device out locally while the server
    /// keeps the token on the old profile.
    @MainActor
    func testResetProfilePreInitIsNoOpUnderParity() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        PreInitMemoryBuffer.shared.reset()
        // Warm start: persisted identity + token, but initialize() has not run this session.
        IdentityStore.shared.update(ProfileData(email: "id@x.com", anonymousId: "anon-keep"))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "tok",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.resetProfile()

        XCTAssertEqual(IdentityStore.shared.current.email, "id@x.com",
                       "pre-init reset must not clear PII")
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anon-keep",
                       "pre-init reset must not mint a new anonymousId")
        XCTAssertTrue(readQueue().isEmpty, "pre-init reset must not enqueue")
    }

    // MARK: - setProfileProperty

    /// setProfileProperty stages the key/value into ProfilePropertyBuffer; it does NOT enqueue.
    @MainActor
    func testSetProfilePropertyStagesIntoBufferNoEnqueue() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setProfileProperty(.firstName, AnyEncodable("Alice"))

        XCTAssertTrue(readQueue().isEmpty,
                      "setProfileProperty must not enqueue directly — staging only")
    }

    /// setProfileProperty: staged values fold into a request on the next buffer flush.
    @MainActor
    func testSetProfilePropertyStagedValueAppearsOnFlush() {
        seedPostInitWithToken()
        let readQueue = seedTestQueueStore()

        KlaviyoCommands.setProfileProperty(.firstName, AnyEncodable("Alice"))

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

    /// Parity gate: pre-init `setProfileProperty` (default flags, no apiKey) is dropped — nothing is
    /// staged, so a later flush enqueues nothing. Mirrors Android/Swift dropping pre-init attributes.
    @MainActor
    func testSetProfilePropertyPreInitDropsUnderParityFlags() {
        // Default parity flags: base setUp resets featureFlags → enablePreInitDiskCapture == false.
        resetCanonicalCoreStores()
        ProfilePropertyBuffer.shared.reset()
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))
        let readQueue = seedTestQueueStore()

        // Pre-init: no apiKey in SDKConfigStore → the property must be dropped, not staged.
        KlaviyoCommands.setProfileProperty(.firstName, AnyEncodable("Alice"))

        let flushExpect = XCTestExpectation(description: "flush")
        Task {
            await ProfilePropertyBuffer.shared.flushIntoQueue()
            flushExpect.fulfill()
        }
        wait(for: [flushExpect], timeout: 2)

        XCTAssertTrue(readQueue().isEmpty,
                      "pre-init profile property must be dropped, not staged for a later flush")
    }

    // MARK: - R4 Regression: 4xx field-clear must not be resurrected by a subsequent setter

    /// R4: if a `RequestQueue` 4xx handler clears an identifier directly on `IdentityStore` (e.g.
    /// clears email due to an invalid-email error), a subsequent `setEmail` call must NOT resurrect
    /// the old cleared value. `IdentityStore` is the canonical store — the cleared field must stay
    /// gone and only the new value from the setter call must appear.
    @MainActor
    func testSetEmailAfter4xxFieldClearDoesNotResurrectClearedIdentifier() {
        // Arrange: start with a post-init state that has an email.
        seedPostInitWithToken(email: "stale@x.com")
        let readQueue = seedTestQueueStore()

        // Simulate a 4xx field-clear: the RequestQueue handler clears the email directly on
        // IdentityStore (the canonical store). The clear is durable — no secondary store can
        // re-persist the stale value.
        IdentityStore.shared.mutate { $0.email = nil }

        XCTAssertNil(IdentityStore.shared.current.email, "sanity: 4xx clear must take effect")

        // Act: call setEmail with a fresh value.
        KlaviyoCommands.setEmail("fresh@x.com")

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
    /// profile (not drop silently).
    @MainActor
    func testSetEmailPreInitWithStoredTokenBuffersProfile() {
        featureFlags.enablePreInitDiskCapture = true
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

        KlaviyoCommands.setEmail("new@example.com")

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
    /// `LifecycleState`/`SessionState` is the gate (not the disk-hydrated `SDKConfigStore.apiKey`),
    /// so a warm-start `setEmail` is treated as pre-init: under default parity flags it is DROPPED
    /// entirely — no request AND no store write — so the same setter after `initialize()` still sends
    /// instead of dedup-no-oping. Matches Android's pre-init drop.
    @MainActor
    func testSetEmailWarmStartPreInitDroppedUnderParity() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        PreInitMemoryBuffer.shared.reset()
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

        KlaviyoCommands.setEmail("new@example.com")

        // Warm-start pre-init: the request must NOT be stamped under the persisted key.
        XCTAssertTrue(readQueue().isEmpty,
                      "warm-start setEmail must not enqueue under the disk-hydrated apiKey")
        // Dropped entirely: the new email must NOT be persisted (so the post-init re-set still sends).
        XCTAssertEqual(IdentityStore.shared.current.email, "old@example.com",
                       "warm-start setEmail must be dropped, not persisted to IdentityStore")
    }

    /// Regression (default parity): a pre-init `setEmail` is dropped WITHOUT persisting, so the same
    /// email after `initialize()` is not a dedup no-op and still sends. Mirrors the token fix.
    @MainActor
    func testSetEmailPreInitDropThenPostInitSends() {
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        PreInitMemoryBuffer.shared.reset()
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))
        let readQueue = seedTestQueueStore()

        // Pre-init (uninitialized, default parity): dropped, not persisted.
        KlaviyoCommands.setEmail("user@x.com")
        XCTAssertNil(IdentityStore.shared.current.email, "pre-init email must not be persisted")
        XCTAssertTrue(readQueue().isEmpty, "pre-init email must not enqueue")

        // Simulate initialize().
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        markSessionInitialized()

        // The SAME email post-init must now send (not a dedup no-op against a stale disk value).
        KlaviyoCommands.setEmail("user@x.com")
        XCTAssertEqual(IdentityStore.shared.current.email, "user@x.com")
        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "post-init setEmail must send after a pre-init drop of the same value")
        guard case .createProfile = queued.first?.endpoint else {
            return XCTFail("expected createProfile, got \(queued.first?.endpoint as Any)")
        }
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

        KlaviyoCommands.setEmail("parity@x.com")

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
