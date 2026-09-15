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
import OSLog

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

    // MARK: - Push token

    /// Registers or updates the push token. Deduplicates against the canonical `IdentityStore` token;
    /// no-ops when token + enablement + background + device metadata all match.
    ///
    /// Post-init (this session's `initialize()` has started): builds a push-token registration request
    /// and enqueues it directly via `QueueStore`.
    /// Pre-init / warm-start: routes through the ungated `RequestEnqueuer` path which re-gates on
    /// `SDKConfigStore` — preserving the old warm-start behavior (token reaches `QueueStore` when
    /// the apiKey is already persisted, buffers otherwise).
    static func setPushToken(_ pushToken: String, _ enablement: PushEnablement) {
        let newTokenData = PushTokenData(
            pushToken: pushToken,
            pushEnablement: enablement,
            pushBackground: environment.getBackgroundSetting(),
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
        // Dedup against the canonical token: skip when all fields match.
        guard IdentityStore.shared.pushToken != newTokenData else { return }
        // Write the new token directly to the canonical store (replaces old write-through-defer).
        IdentityStore.shared.updatePushToken(newTokenData)
        guard let anonymousId = IdentityStore.shared.current.anonymousId else {
            environment.emitDeveloperWarning("SDK internal error: missing anonymousId")
            return
        }
        // Gate on LifecycleState (session-fresh), not SDKConfigStore (persisted across launches).
        // Same boundary as applyIdentifierChange: `state.apiKey` was nil until `.initializing`,
        // even when SDKConfigStore already held a persisted key from a prior launch.
        if LifecycleState.shared.current != .uninitialized,
           let apiKey = SDKConfigStore.shared.current.apiKey {
            // Post-init: register the token against the current identity.
            let request = resolvedTokenRequest(
                identity: IdentityStore.shared.current,
                apiKey: apiKey,
                anonymousId: anonymousId,
                pushToken: pushToken,
                enablement: enablement
            )
            QueueStore.shared.enqueue(request)
        } else {
            // Pre-init or warm start: RequestEnqueuer re-gates on SDKConfigStore.
            RequestEnqueuer.enqueuePushToken(pushToken, enablement: enablement)
        }
    }

    /// Forwards an automatic (APNs-delivered) token to `setPushToken`. Identical routing semantics:
    /// post-init → `QueueStore`; pre-init/warm-start → `RequestEnqueuer`.
    ///
    /// In the old reducer this was an async re-dispatch (`.run { send(.setPushToken(...)) }`);
    /// here it is a direct synchronous call — more deterministic, same observable behavior.
    static func setAutomaticPushToken(_ pushToken: String, _ enablement: PushEnablement) {
        setPushToken(pushToken, enablement)
    }

    /// Updates the push-enablement on the canonical token. Reads the token from `IdentityStore`
    /// (not a stale local copy) so a prior `setPushToken` rotation is not silently reverted.
    /// No-ops if no token has been registered yet.
    static func setPushEnablement(_ enablement: PushEnablement) {
        guard let pushToken = IdentityStore.shared.pushToken?.pushToken else { return }
        setPushToken(pushToken, enablement)
    }

    // MARK: - Profile & subscription

    /// Syncs a `Profile` to Klaviyo. Reproduces the conditional-reset logic of the
    /// `enqueueProfile` reducer case (StateManagement.swift:374-410):
    ///
    /// 1. Detect identifier changes vs. the canonical `IdentityStore` identity.
    /// 2. If the profile *was* identified AND identifiers changed → mint a fresh `anonymousId`
    ///    and clear prior PII (prevents two users merging onto one profile).
    ///    Also clears `ProfilePropertyBuffer` (mirrors `KlaviyoState.reset`).
    /// 3. Apply `updateStateWithProfile`-equivalent field logic.
    /// 4. Skip the API call if identifiers are unchanged and the profile carries no extra attrs.
    /// 5. Enqueue a `createProfile` via `RequestEnqueuer` (ungated — parity with the reducer).
    /// 6. If a push token existed before the reset → enqueue a separate identity-only token
    ///    re-registration so FIFO keeps the profile ahead.
    ///
    /// NOTE: both enqueues use `RequestEnqueuer` (not the `LifecycleState`/`QueueStore` gate)
    /// for parity with the existing reducer case.
    static func enqueueProfile(_ profile: Profile) {
        // Capture the canonical token BEFORE any identity mutation so a reset can't lose it.
        let tokenData = IdentityStore.shared.pushToken

        // Compute identifier change against the current canonical identity.
        let current = IdentityStore.shared.current
        let currentIds: [String?] = [current.email, current.phoneNumber, current.externalId]
        let incomingIds: [String?] = [
            profile.email?.trimWhiteSpaceOrReturnNilIfEmpty(),
            profile.phoneNumber?.trimWhiteSpaceOrReturnNilIfEmpty(),
            profile.externalId?.trimWhiteSpaceOrReturnNilIfEmpty()
        ]
        let identifiersChanged = currentIds != incomingIds

        // Atomically apply the identity update to IdentityStore.
        var updated = ProfileData()
        IdentityStore.shared.mutate { profile in
            if profile.email != nil || profile.phoneNumber != nil || profile.externalId != nil,
               identifiersChanged {
                // Identified → identifier change: mint a fresh anonymousId and drop prior PII
                // so this call does not merge two people onto one Klaviyo profile.
                // The canonical push token lives outside ProfileData — do NOT touch it here.
                profile.anonymousId = IdentityStore.shared.mintNewAnonymousId()
                profile.email = nil
                profile.phoneNumber = nil
                profile.externalId = nil
            }
            // Apply updateStateWithProfile-equivalent field logic: set each identifier from the
            // incoming profile when non-empty and changed relative to the (possibly just-reset) value.
            if let incomingEmail = incomingIds[0],
               incomingEmail.isNotEmptyOrSame(as: profile.email, identifier: "email") {
                profile.email = incomingEmail
            }
            if let incomingPhone = incomingIds[1],
               incomingPhone.isNotEmptyOrSame(as: profile.phoneNumber, identifier: "phone number") {
                profile.phoneNumber = incomingPhone
            }
            if let incomingExtId = incomingIds[2],
               incomingExtId.isNotEmptyOrSame(as: profile.externalId, identifier: "external id") {
                profile.externalId = incomingExtId
            }
            updated = profile // capture post-mutation identity for enqueue below
        }

        // Clear staged profile properties — mirrors KlaviyoState.reset.
        // Must run OUTSIDE mutate (writeLock is non-reentrant) and only when reset actually fired.
        let wasIdentified = current.email != nil || current.phoneNumber != nil || current.externalId != nil
        if wasIdentified, identifiersChanged {
            ProfilePropertyBuffer.shared.reset()
        }

        // Skip API call when there is nothing new to sync.
        if !identifiersChanged, !profile.hasNonIdentifierData { return }

        guard let anonymousId = updated.anonymousId else { return }

        // Enqueue the profile via ungated RequestEnqueuer (parity: reducer used RequestEnqueuer here).
        RequestEnqueuer.enqueueProfile(
            payload: CreateProfilePayload(
                data: profilePayload(from: profile, identity: updated, anonymousId: anonymousId)
            )
        )

        // Re-register the token under the (potentially new) identity as a SEPARATE identity-only
        // request, enqueued AFTER the createProfile so FIFO keeps the profile ahead.
        if let tokenData {
            RequestEnqueuer.enqueuePushToken(tokenData.pushToken, enablement: tokenData.pushEnablement)
        }
    }

    /// Enqueues a channel-subscription request. Validates channels against the current identity and
    /// emits a developer warning (returning early) when required identifiers are missing.
    static func enqueueSubscription(_ subscription: Subscription) {
        guard let anonymousId = IdentityStore.shared.current.anonymousId,
              let payload = buildSubscriptionPayload(
                  identity: IdentityStore.shared.current,
                  anonymousId: anonymousId,
                  subscription: subscription
              )
        else { return }
        RequestEnqueuer.enqueueSubscription(payload: payload)
    }

    // MARK: - Event & tracking-link orchestration

    /// Enqueues an event via `RequestEnqueuer` (always, even pre-init).
    ///
    /// Post-`initialized` only: stamps the current canonical identity onto a copy of the event,
    /// then publishes it to `EventBus` (drives event-triggered in-app forms). High-priority events
    /// additionally trigger an immediate `flushNow()` on the Core request-queue actor.
    ///
    /// ⚠️ Gate distinction: the publish + flush are gated on STRICT `.initialized`
    /// (`LifecycleState.shared.current == .initialized`), NOT the `.initializing` boundary used by
    /// the identity setters. This matches the old reducer's `guard case .initialized = state`.
    static func enqueueEvent(_ event: Event) {
        RequestEnqueuer.enqueueEvent(event)
        guard LifecycleState.shared.current == .initialized else { return }
        let identity = IdentityStore.shared.current
        let publishedEvent = event.updateEventWithIdentifiers(
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            pushToken: IdentityStore.shared.pushToken?.pushToken
        )
        // Preserve fireAndForget semantics: publish asynchronously so an EventBus subscriber
        // cannot re-enter this call synchronously. `enrichAndPublishEvent` is a plain function
        // (no actor isolation), so `Task.detached` is the right async boundary.
        if event.priority == .high {
            Task { await klaviyoSwiftEnvironment.requestQueue.flushNow() }
        }
        Task.detached { enrichAndPublishEvent(publishedEvent) }
    }

    /// Enqueues an aggregate-event payload directly via `RequestEnqueuer`. No init gate.
    static func enqueueAggregateEvent(_ payload: Data) {
        RequestEnqueuer.enqueueAggregateEvent(payload)
    }

    /// Receives a Klaviyo click-tracking URL, resolves it to its destination via
    /// `TrackingLinkManager`, and either opens the destination or enqueues a click-log.
    ///
    /// - Stamps `clickTime` before the async network call (parity with reducer's `environment.date()`).
    /// - Reads identity from `IdentityStore.shared.current` (parity: reducer read from state).
    /// - Resolution is NOT init-gated (matches the reducer — tracking-link opens can happen
    ///   even before `initialize()` completes).
    static func trackingLinkReceived(_ url: URL) {
        let clickTime = environment.date()
        if #available(iOS 14.0, *) {
            Logger.stateLogger.info(
                "Attempting to resolve tracking link destination from tracking URL '\(url.absoluteString)'"
            )
        }
        let identity = IdentityStore.shared.current
        let profileInfo = ProfilePayload(
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            anonymousId: identity.anonymousId ?? ""
        )
        Task {
            let outcome = await TrackingLinkManager.resolveDestination(
                trackingLink: url,
                profileInfo: profileInfo
            )
            switch outcome {
            case let .resolved(destinationURL):
                await DeepLinkManager.openDeepLink(destinationURL)
            case .failed:
                trackingLinkResolutionFailed(trackingLink: url, clickTime: clickTime)
            }
        }
    }

    /// Enqueues a tracking-link click-log request via `RequestEnqueuer`.
    ///
    /// Identity is resolved inside `RequestEnqueuer.enqueueTrackingLinkClicked` from the canonical
    /// `IdentityStore`. Uses the ungated enqueuer: routes to `QueueStore` when an apiKey is present,
    /// or buffers durably pre-init.
    static func trackingLinkResolutionFailed(trackingLink: URL, clickTime: Date) {
        RequestEnqueuer.enqueueTrackingLinkClicked(trackingLink: trackingLink, clickTime: clickTime)
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
