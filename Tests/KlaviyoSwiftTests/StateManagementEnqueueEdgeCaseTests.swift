//
//  StateManagementEnqueueEdgeCaseTests.swift
//  Pre-init buffering and enqueueProfile conditional-reset edge cases.
//  Split from StateManagementEdgeCaseTests to stay within SwiftLint type_body_length.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

class StateManagementEnqueueEdgeCaseTests: StateManagementTestCase {
    // MARK: - set enqueue event uninitialized

    @MainActor
    func testHighPriorityEventUninitializedRoutesToBuffer() async throws {
        let store = TestStore(initialState: .init(), reducer: KlaviyoReducer())
        // Pre-init events (any priority) now route to the durable UnattributedBuffer.
        let event = Event(name: ._openedPush, priority: .high)
        _ = await store.send(.enqueueEvent(event))
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1)
    }

    @MainActor
    func testStandardPriorityEventUninitializedRoutesToBuffer() async throws {
        let store = TestStore(initialState: .init(), reducer: KlaviyoReducer())

        // Pre-init events are no longer dropped with a warning; every one buffers durably.
        for eventName in Event.EventName.allCases {
            let event = Event(name: eventName)
            _ = await store.send(.enqueueEvent(event))
        }

        XCTAssertEqual(
            UnattributedBuffer.shared.drainSnapshot().requests.count,
            Event.EventName.allCases.count,
            "every pre-init event is buffered"
        )
    }

    // MARK: - set profile uninitialized

    @MainActor
    func testSetProfileUnitializedRoutesToBuffer() async throws {
        let store = TestStore(initialState: .init(), reducer: KlaviyoReducer())
        store.exhaustivity = .off
        let profile = Profile(email: "foo")
        // Pre-init: the identifier is folded into IdentityStore and a profile sync is buffered.
        _ = await store.send(.enqueueProfile(profile))

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1, "pre-init profile is buffered, not dropped")
        guard case let .profile(payload) = buffered.first else {
            return XCTFail("expected a buffered profile request")
        }
        XCTAssertEqual(
            payload.data.attributes.email, "foo",
            "the just-set email reaches the buffered profile payload"
        )
    }

    @MainActor
    func testPreInitEnqueueProfileCarriesStructuredAttributesToBuffer() async throws {
        let store = TestStore(initialState: .init(), reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // A pre-init profile carrying structured attributes (name/title/org/location/image) must
        // reach the durable buffer in full, so it syncs completely after initialize() — parity
        // with the initialized path, closing the MAGE-952 regression (MAGE-1141).
        let profile = Profile(
            email: "ada@example.com",
            firstName: "Ada",
            lastName: "Lovelace",
            organization: "Analytical Engines",
            title: "Countess",
            image: "https://example.com/ada.png",
            location: .init(city: "London"),
            properties: ["plan": "premium"]
        )
        _ = await store.send(.enqueueProfile(profile))

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1, "pre-init structured profile is buffered")
        guard case let .profile(payload) = buffered.first else {
            return XCTFail("expected a buffered profile request")
        }
        let attributes = payload.data.attributes
        XCTAssertEqual(attributes.email, "ada@example.com")
        XCTAssertEqual(attributes.firstName, "Ada")
        XCTAssertEqual(attributes.lastName, "Lovelace")
        XCTAssertEqual(attributes.organization, "Analytical Engines")
        XCTAssertEqual(attributes.title, "Countess")
        XCTAssertEqual(attributes.image, "https://example.com/ada.png")
        XCTAssertEqual(attributes.location?.city, "London")
    }

    // MARK: - pre-init structured attributes are carried (no warning)

    @MainActor
    func testPreInitEnqueueProfileDoesNotWarnEvenWithStructuredAttributes() async throws {
        var warnings: [String] = []
        environment.emitDeveloperWarning = { warnings.append($0) }

        let store = TestStore(initialState: .init(), reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // The buffer now carries the full payload (MAGE-1141), so a pre-init profile — including one
        // with structured attributes — no longer emits the dropped-attribute developer warning.
        _ = await store.send(.enqueueProfile(Profile(email: "a@b.com", firstName: "Ada")))
        _ = await store.send(.enqueueProfile(Profile(email: "c@d.com", properties: ["plan": "free"])))

        XCTAssertTrue(
            warnings.isEmpty,
            "no dropped-attribute warning expected once structured attributes are carried"
        )
    }

    @MainActor
    func testSetProfileWithEmptyStringIdentifiers() async throws {
        let initialState = identifiedState(email: "foo@bar.com", phoneNumber: "99999999", externalId: "12345")
        let readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueProfile(Profile(email: "", phoneNumber: "", externalId: ""))) {
            $0.email = nil // since we reset state
            $0.phoneNumber = nil // since we reset state
            $0.externalId = nil // since we reset state
            $0.pushTokenData = nil
        }
        // reset fires with preserveTokenData: false, but the captured pushTokenData is used
        // to build a token request in the reducer before the reset clears state.
        let request = expectedTokenRequest(
            apiKey: TEST_API_KEY,
            tokenData: initialState.pushTokenData!,
            profile: Profile(email: nil, phoneNumber: nil, externalId: nil),
            anonymousId: store.state.anonymousId!
        )
        XCTAssertEqual(readQueue(), [request])
    }

    // MARK: - enqueueProfile: conditional reset (push-token storm fix)

    @MainActor
    func testSetProfileSameIdentifiersDoesNotReset() async throws {
        // When setProfile is called with the same identifiers that are already on state,
        // reset() should NOT fire — anonymousId stays the same, no spurious push-token request.
        let initialState = identifiedState(
            email: "same@email.com",
            phoneNumber: "+15555555555",
            externalId: "ext-123"
        )
        let readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Same identifiers + no non-identifier attributes → no reset, no API call, no state change.
        // Nothing changed, so there's no reason to hit the network.
        // The pushTokenData and anonymousId both remain untouched on state.
        _ = await store.send(.enqueueProfile(
            Profile(email: "same@email.com", phoneNumber: "+15555555555", externalId: "ext-123")
        ))
        XCTAssertTrue(readQueue().isEmpty, "identical identifiers must not enqueue a request")
    }

    @MainActor
    func testSetProfileDifferentIdentifiersResetsState() async throws {
        // When setProfile is called with different identifiers, reset() SHOULD fire,
        // regenerating the anonymousId and clearing pushTokenData.
        let initialState = identifiedState(
            email: "old@email.com",
            phoneNumber: "+11111111111",
            externalId: "old-ext"
        )

        let readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.enqueueProfile(
            Profile(email: "new@email.com", phoneNumber: "+12222222222", externalId: "new-ext")
        )) {
            // reset() fires → identifiers cleared, then updateStateWithProfile sets new ones
            $0.email = "new@email.com"
            $0.phoneNumber = "+12222222222"
            $0.externalId = "new-ext"
            // pushTokenData cleared by reset
            $0.pushTokenData = nil
        }
        // Since pushTokenData existed before reset, the reducer uses it to build a token request.
        let request = expectedTokenRequest(
            apiKey: TEST_API_KEY,
            tokenData: initialState.pushTokenData!,
            profile: Profile(email: "new@email.com", phoneNumber: "+12222222222", externalId: "new-ext"),
            anonymousId: store.state.anonymousId!
        )
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testSetProfileSameIdentifiersDifferentAttributesStillUpdates() async throws {
        // Same identifiers but different non-identifier attributes (e.g. firstName) —
        // should NOT reset, but attributes should still be sent in the profile request.
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "same@email.com",
            anonymousId: environment.uuid().uuidString,
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )

        let readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // No pushTokenData → a createProfile request is generated instead of registerPushToken
        let profile = Profile(email: "same@email.com", firstName: "NewName")
        _ = await store.send(.enqueueProfile(profile))
        // A createProfile request should be enqueued with the updated attributes.
        let profilePayload = ProfilePayload(
            profile,
            email: store.state.email,
            phoneNumber: store.state.phoneNumber,
            externalId: store.state.externalId,
            anonymousId: store.state.anonymousId!
        )
        let request = KlaviyoRequest(
            endpoint: .createProfile(TEST_API_KEY, CreateProfilePayload(data: profilePayload))
        )
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testSetProfilePartialIdentifierMatchStillResets() async throws {
        // If only one identifier changes (e.g. email changes, phone stays same),
        // reset should still fire.
        let initialState = identifiedState(email: "old@email.com", phoneNumber: "+15555555555")

        let readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Email changes, phone stays the same → identifiersChanged = true
        _ = await store.send(
            .enqueueProfile(Profile(email: "different@email.com", phoneNumber: "+15555555555"))
        ) {
            // reset() fires
            $0.email = "different@email.com"
            $0.phoneNumber = "+15555555555"
            $0.pushTokenData = nil
        }
        let request = expectedTokenRequest(
            apiKey: TEST_API_KEY,
            tokenData: initialState.pushTokenData!,
            profile: Profile(email: "different@email.com", phoneNumber: "+15555555555"),
            anonymousId: store.state.anonymousId!
        )
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testSetProfileNilIdentifiersTriggersResetWhenStateHasIdentifiers() async throws {
        // All-nil incoming identifiers differ from non-nil state identifiers,
        // so reset fires — preserving the old "clobbering" setProfile behavior.
        let initialState = identifiedState(
            email: "existing@email.com",
            phoneNumber: "+15555555555",
            externalId: "ext-id"
        )

        let readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Profile with all-nil identifiers → [nil,nil,nil] != [email,phone,extId] → reset fires
        let profile = Profile(firstName: "JustAName")
        _ = await store.send(.enqueueProfile(profile)) {
            // reset(preserveTokenData: false) fires → identifiers cleared, pushTokenData nil
            $0.email = nil
            $0.phoneNumber = nil
            $0.externalId = nil
            $0.pushTokenData = nil
        }
        // pushTokenData existed before reset, so a token request is built with captured data.
        let request = expectedTokenRequest(
            apiKey: TEST_API_KEY,
            tokenData: initialState.pushTokenData!,
            profile: profile,
            anonymousId: store.state.anonymousId!
        )
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testResetProfileStillClobbersAllState() async throws {
        // resetProfile() should always clobber all state, regardless of identifiers.
        let initialState = identifiedState(
            email: "user@email.com",
            phoneNumber: "+15555555555",
            externalId: "ext-123"
        )

        let readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.resetProfile) {
            // reset(preserveTokenData: true) is the default for resetProfile
            $0.email = nil
            $0.phoneNumber = nil
            $0.externalId = nil
            $0.pendingProfile = nil
            // pushTokenData is preserved and a new token request is enqueued
            // anonymousId is regenerated since the profile was identified
            $0.pushTokenData = initialState.pushTokenData
        }
        let request = expectedTokenRequest(
            apiKey: TEST_API_KEY,
            tokenData: initialState.pushTokenData!,
            profile: Profile(),
            anonymousId: store.state.anonymousId!
        )
        XCTAssertEqual(readQueue(), [request])
    }

    @MainActor
    func testPreInitResetProfileClearsPersistedIdentity() async throws {
        // Pre-init reset must clear the persisted identity (drop PII, mint a fresh anon) so a reset
        // issued before initialize() doesn't leave the prior profile in IdentityStore (MAGE-1136).
        IdentityStore.shared.update(
            ProfileData(email: "user@email.com", externalId: "ext-123", anonymousId: "anon-old")
        )
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.resetProfile)

        let identity = IdentityStore.shared.current
        XCTAssertNil(identity.email, "pre-init reset clears persisted email")
        XCTAssertNil(identity.externalId, "pre-init reset clears persisted externalId")
        XCTAssertNotNil(identity.anonymousId)
        XCTAssertNotEqual(
            identity.anonymousId, "anon-old", "pre-init reset mints a fresh anonymousId"
        )
    }

    @MainActor
    func testPreInitResetProfileRebuffersPersistedPushToken() async throws {
        // Parity with post-init reset(preserveTokenData: true): a persisted push token is
        // re-registered against the freshly minted anon. Pre-init that register routes through the
        // ungated RequestEnqueuer and lands in the durable buffer (MAGE-1136).
        IdentityStore.shared.update(ProfileData(email: "user@email.com", anonymousId: "anon-old"))
        IdentityStore.shared.updatePushToken(
            PushTokenData(
                pushToken: "tok-1", pushEnablement: .authorized, pushBackground: .available,
                deviceData: DeviceMetadata(context: environment.appContextInfo())
            )
        )
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.resetProfile)

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        let hasTokenRegister = buffered.contains {
            if case .pushToken = $0 { return true }
            return false
        }
        XCTAssertTrue(
            hasTokenRegister,
            "persisted push token is re-registered into the buffer after a pre-init reset"
        )
    }

    // MARK: - Helpers

    /// Builds a fully-initialized, identified `KlaviyoState` for tests that differ only in identifiers.
    private func identifiedState(
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        pushToken: String? = "blob_token"
    ) -> KlaviyoState {
        KlaviyoState(
            apiKey: TEST_API_KEY,
            email: email,
            anonymousId: environment.uuid().uuidString,
            phoneNumber: phoneNumber,
            externalId: externalId,
            pushTokenData: pushToken.map { token in
                .init(
                    pushToken: token,
                    pushEnablement: .authorized,
                    pushBackground: .available,
                    deviceData: .init(context: environment.appContextInfo())
                )
            },
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true
        )
    }

    private func expectedTokenRequest(
        apiKey: String,
        tokenData: PushTokenData,
        profile: Profile,
        anonymousId: String
    ) -> KlaviyoRequest {
        KlaviyoRequest(
            endpoint: .registerPushToken(
                apiKey,
                PushTokenPayload(
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement.rawValue,
                    background: tokenData.pushBackground.rawValue,
                    profile: ProfilePayload(profile, anonymousId: anonymousId)
                )
            )
        )
    }

    // MARK: - Pre-init set(profile:) identifier-change reset (cursor bugbot regression)

    /// A pre-init `set(profile:)` with DIFFERENT identifiers than the persisted profile must mint a
    /// fresh anonymousId (mirroring the initialized path), so a later launch identifying a new user
    /// before `initialize()` doesn't inherit the previous user's anon and merge two people.
    @MainActor
    func testPreInitEnqueueProfileWithDifferentIdentifiersMintsNewAnonymousId() async throws {
        // A persisted identified profile from a previous session.
        let previousAnon = "previous-user-anon"
        IdentityStore.shared.update(ProfileData(email: "old@user.com", anonymousId: previousAnon))

        let store = TestStore(initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.enqueueProfile(Profile(email: "new@user.com")))

        XCTAssertNotEqual(
            IdentityStore.shared.current.anonymousId, previousAnon,
            "changed pre-init identifiers must mint a new anonymousId, not reuse the prior user's"
        )
        XCTAssertEqual(IdentityStore.shared.current.email, "new@user.com")
        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1,
                       "the profile sync is buffered pre-init")
    }

    /// A pre-init `set(profile:)` with the SAME identifiers must NOT churn the anonymousId.
    @MainActor
    func testPreInitEnqueueProfileWithSameIdentifiersPreservesAnonymousId() async throws {
        let anon = "stable-anon"
        IdentityStore.shared.update(ProfileData(email: "same@user.com", anonymousId: anon))

        let store = TestStore(initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.enqueueProfile(Profile(email: "same@user.com")))

        XCTAssertEqual(IdentityStore.shared.current.anonymousId, anon,
                       "unchanged identifiers must preserve the anonymousId")
    }

    /// A pre-init identifier setter (setEmail/setPhoneNumber/setExternalId) must FOLD onto the
    /// persisted identity, not replace it with a partial one. Regression: a later launch that set a
    /// single identifier before `initialize()` wiped the other persisted identifiers (IdentityStore
    /// replaces wholesale). Mirrors the fold the pre-init `set(profile:)` path already does.
    @MainActor
    func testPreInitSetEmailPreservesOtherPersistedIdentifiers() async throws {
        let anon = "stable-anon"
        IdentityStore.shared.update(ProfileData(
            phoneNumber: "+15555550100", externalId: "ext-1", anonymousId: anon
        ))

        let store = TestStore(initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.setEmail("new@user.com"))

        let stored = IdentityStore.shared.current
        XCTAssertEqual(stored.email, "new@user.com")
        XCTAssertEqual(stored.phoneNumber, "+15555550100", "pre-init setEmail must not wipe the persisted phone")
        XCTAssertEqual(stored.externalId, "ext-1", "pre-init setEmail must not wipe the persisted externalId")
        XCTAssertEqual(stored.anonymousId, anon)
    }
}

extension Event.EventName: CaseIterable {
    public static var allCases: [KlaviyoCore.Event.EventName] {
        [._openedPush, .openedAppMetric, .viewedProductMetric, .addedToCartMetric,
         .startedCheckoutMetric, .customEvent("someEvent")]
    }
}
