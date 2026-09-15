//
//  KlaviyoOrchestration.swift
//
//
//  Created by Isobelle Lim on 9/14/26.
//
//  Direct orchestration functions that replace the identity-setter cases in `KlaviyoReducer`.
//  These are ADDITIVE and UNWIRED — the reducer still runs; nothing calls these functions yet.
//  A later task flips production over by replacing the reducer dispatch sites.
//
//  Design contract:
//  - Each public setter is a direct call, not a TCA action dispatch.
//  - The TOCTOU `state.identity = current; apply; update(state.identity)` is replaced by a single
//    atomic `IdentityStore.shared.mutate { ... }`.
//  - `IdentityStore.shared.pushToken` is read AFTER `mutate` returns (writeLock is non-reentrant).
//  - The post-init gate checks `LifecycleState.shared.current != .uninitialized` (session-fresh,
//    equivalent to the old `state.apiKey != nil`); the apiKey VALUE is read from `SDKConfigStore`.

import AnyCodable
import Foundation
import KlaviyoCore

/// Namespace for direct orchestration functions that mirror the identity-setter reducer cases.
enum KlaviyoOrchestration {
    // MARK: - Identity setters

    /// Sets the profile email. Guards against empty strings and same-value re-sets (no-op).
    /// Post-init with a token → enqueues a token re-association via `QueueStore`.
    /// Pre-init or no token → buffers a profile via `RequestEnqueuer`.
    static func setEmail(_ email: String) {
        guard email.isNotEmptyOrSame(as: IdentityStore.shared.current.email, identifier: "email") else {
            return
        }
        applyIdentifierChange { $0.email = email.trimWhiteSpaceOrReturnNilIfEmpty() }
    }

    /// Sets the profile phone number. Same guard and routing logic as `setEmail`.
    static func setPhoneNumber(_ phoneNumber: String) {
        guard phoneNumber.isNotEmptyOrSame(
            as: IdentityStore.shared.current.phoneNumber, identifier: "phone number"
        ) else {
            return
        }
        applyIdentifierChange { $0.phoneNumber = phoneNumber.trimWhiteSpaceOrReturnNilIfEmpty() }
    }

    /// Sets the profile external ID. Same guard and routing logic as `setEmail`.
    static func setExternalId(_ externalId: String) {
        guard externalId.isNotEmptyOrSame(
            as: IdentityStore.shared.current.externalId, identifier: "external id"
        ) else {
            return
        }
        applyIdentifierChange { $0.externalId = externalId.trimWhiteSpaceOrReturnNilIfEmpty() }
    }

    // MARK: - Profile reset

    /// Resets the profile to an anonymous state. If the profile was identified, mints a fresh
    /// `anonymousId`. Clears all PII and staged profile properties. Re-registers the push token
    /// (if one exists) under the new anonymous identity.
    ///
    /// Ports `KlaviyoState.reset(preserveTokenData: false)` + the surrounding `.resetProfile` case.
    static func resetProfile() {
        // Capture the token BEFORE the mutate so we can re-register after.
        // (We must not call IdentityStore inside the mutate closure — writeLock is non-reentrant.)
        let tokenBeforeReset = IdentityStore.shared.pushToken

        IdentityStore.shared.mutate { profile in
            if profile.email != nil || profile.phoneNumber != nil || profile.externalId != nil {
                // Identified profile → mint a fresh anonymousId so the resulting anonymous profile
                // is distinct from the prior identified one.
                profile.anonymousId = IdentityStore.shared.mintNewAnonymousId()
            }
            // Clear all PII. anonymousId stays (freshly minted or was already anonymous).
            profile.email = nil
            profile.phoneNumber = nil
            profile.externalId = nil
        }
        // Clear staged profile properties (mirrors KlaviyoState.reset).
        // Must run AFTER mutate returns — keep the mutate closure purely identity-focused
        // and avoid an unrelated side effect running while the write-lock is held.
        ProfilePropertyBuffer.shared.reset()

        guard let tokenData = tokenBeforeReset else { return }
        // Re-register the token under the new anonymous identity. Uses the ungated
        // `RequestEnqueuer` path — matching the reducer — so it routes to QueueStore when apiKey
        // is present, and buffers otherwise.
        RequestEnqueuer.enqueuePushToken(tokenData.pushToken, enablement: tokenData.pushEnablement)
    }

    // MARK: - Profile property staging

    /// Stages a profile property into `ProfilePropertyBuffer`. The Core `RequestQueue` folds staged
    /// props into the outbound request via `willDrain` (`ProfilePropertyBuffer.flushIntoQueue`)
    /// just before each drain. Does NOT enqueue directly.
    static func setProfileProperty(_ key: Profile.ProfileKey, _ value: AnyEncodable) {
        ProfilePropertyBuffer.shared.stage(key, value)
    }

    // MARK: - Private helpers

    /// Applies a field-level change to the profile atomically via `IdentityStore.mutate`, then
    /// enqueues the appropriate follow-up sync request:
    ///
    /// - **Post-init + token present:** enqueues a token re-association request via `QueueStore`.
    ///   "Post-init" means `LifecycleState.shared.current != .uninitialized` — i.e. `initialize()`
    ///   has been called this session. This matches the old reducer's `state.apiKey != nil` gate:
    ///   `state.apiKey` was set at the `.initializing` transition and was nil on warm-start before
    ///   `initialize()` ran, even if `SDKConfigStore` already held a persisted key.
    ///
    /// - **Pre-init or no token:** enqueues a profile via the ungated `RequestEnqueuer` (lands in
    ///   the durable `UnattributedBuffer` pre-init, or directly in `QueueStore` on warm-start after
    ///   `RequestEnqueuer` re-gates on `SDKConfigStore`).
    ///
    /// The `apply` closure must be pure and must NOT call back into `IdentityStore` — the store's
    /// `writeLock` is non-reentrant.
    private static func applyIdentifierChange(_ apply: (inout ProfileData) -> Void) {
        var updated = ProfileData()
        IdentityStore.shared.mutate { profile in
            apply(&profile)
            updated = profile // capture post-mutation identity for enqueue below
        }
        guard let anonymousId = updated.anonymousId else { return }

        // Read the token AFTER mutate returns (non-reentrant writeLock).
        // Gate on LifecycleState (session-fresh), not SDKConfigStore (persisted across launches).
        // On a warm start, SDKConfigStore may already hold the prior session's apiKey even before
        // initialize() runs — matching state.apiKey requires checking that this session's
        // initialize() has started.
        if LifecycleState.shared.current != .uninitialized,
           let apiKey = SDKConfigStore.shared.current.apiKey,
           let tokenData = IdentityStore.shared.pushToken {
            // Post-init with a token: re-associate the token to the new identity.
            let request = resolvedTokenRequest(
                identity: updated,
                apiKey: apiKey,
                anonymousId: anonymousId,
                pushToken: tokenData.pushToken,
                enablement: tokenData.pushEnablement
            )
            QueueStore.shared.enqueue(request)
        } else {
            // Pre-init or post-init with no token: send a profile via the ungated RequestEnqueuer.
            // Empty `Profile()` is intentional — `profilePayload(from:identity:anonymousId:)` reads
            // all identifiers from `identity`, so the argument only carries redundant values.
            // On warm start (pre-init, SDKConfigStore has persisted apiKey), RequestEnqueuer
            // re-gates on SDKConfigStore and routes directly to QueueStore — no buffer needed.
            let payload = CreateProfilePayload(
                data: profilePayload(from: Profile(), identity: updated, anonymousId: anonymousId)
            )
            RequestEnqueuer.enqueueProfile(payload: payload)
        }
    }
}
