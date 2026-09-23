//
//  KlaviyoCommands+Initialize.swift
//
//
//  Created by Isobelle Lim on 9/15/26.
//
//  Initialize + lifecycle orchestration. Drives the SDK's uninitialized→initializing→initialized
//  state machine and the long-lived Core RequestQueue loop.
//

import Combine
import Foundation
import KlaviyoCore
import OSLog

extension KlaviyoCommands {
    // MARK: - Initialize (sync head + async tail)

    /// Confirms or sets the API key, handles company switches, and kicks the async tail.
    ///
    /// Three branches:
    ///  1. **Already initialized** — runtime company switch.
    ///  2. **Cold-start company switch** — uninitialized + persisted prior key differs.
    ///  3. **Fall-through** — normal cold-start init.
    static func initialize(_ apiKey: String) {
        // ── Branch 1: ALREADY INITIALIZED — runtime company switch ───────────────────────────────
        if LifecycleState.shared.current == .initialized {
            let currentKey = SDKConfigStore.shared.current.apiKey
            guard apiKey != currentKey else {
                // Same key: no-op.
                return
            }
            // Unregister the OLD company's token BEFORE switching.
            if let oldKey = currentKey,
               let anonymousId = IdentityStore.shared.current.anonymousId,
               let tokenData = IdentityStore.shared.pushToken {
                let request = RequestFactory.unregisterRequest(
                    identity: RequestIdentity(
                        apiKey: oldKey,
                        anonymousId: anonymousId,
                        email: IdentityStore.shared.current.email,
                        phoneNumber: IdentityStore.shared.current.phoneNumber,
                        externalId: IdentityStore.shared.current.externalId
                    ),
                    pushToken: tokenData.pushToken
                )
                QueueStore.shared.enqueue(request)
            }

            // Switch the config to the new company.
            SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))

            let previousPushTokenData = IdentityStore.shared.pushToken
            if featureFlags.enableCompanySwitchReset {
                // iOS behavior: mint a fresh anon for an identified profile, clear PII, reset staged props.
                IdentityStore.shared.mutate { profile in
                    if profile.email != nil || profile.phoneNumber != nil || profile.externalId != nil {
                        profile.anonymousId = IdentityStore.shared.mintNewAnonymousId()
                    }
                    profile.email = nil
                    profile.phoneNumber = nil
                    profile.externalId = nil
                }
                ProfilePropertyBuffer.shared.reset()
            }
            // Parity (flag OFF): keep the existing profile (PII + anon) and staged props untouched.

            // Re-register the token under the NEW apiKey (gated: apiKey + anonymousId + tokenData).
            if let newAnon = IdentityStore.shared.current.anonymousId,
               let tokenData = previousPushTokenData {
                let profile: ProfilePayload = featureFlags.enableCompanySwitchReset
                    ? ProfilePayload(email: nil, phoneNumber: nil, externalId: nil, anonymousId: newAnon)
                    : RequestBuilding.profilePayload(
                        from: Profile(), identity: IdentityStore.shared.current, anonymousId: newAnon
                    )
                let request = RequestFactory.tokenRequest(
                    apiKey: apiKey,
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement,
                    background: tokenData.pushBackground.rawValue,
                    profile: profile
                )
                QueueStore.shared.enqueue(request)
            }

            // Prompt an immediate flush so the unregister drains promptly.
            Task { await klaviyoSwiftEnvironment.requestQueue.flushNow() }
            return
        }

        // ── Branch 2: COLD-START COMPANY SWITCH ──────────────────────────────────────────────────
        // Uninitialized + a prior key is persisted and differs from the incoming one.
        // Identity + push token are device-scoped in the Core stores and still hold the PREVIOUS
        // company's profile. Mirror the runtime branch so a fresh launch under a new apiKey does
        // not bleed prior PII into the new company or leave its push token registered.
        // Sourced from the stores (not from state, which is empty on cold start).
        if LifecycleState.shared.current == .uninitialized,
           let previousApiKey = SDKConfigStore.shared.current.apiKey,
           previousApiKey != apiKey {
            let previous = IdentityStore.shared.current
            if let anonymousId = previous.anonymousId, let tokenData = IdentityStore.shared.pushToken {
                let request = RequestFactory.unregisterRequest(
                    identity: RequestIdentity(
                        apiKey: previousApiKey,
                        anonymousId: anonymousId,
                        email: previous.email,
                        phoneNumber: previous.phoneNumber,
                        externalId: previous.externalId
                    ),
                    pushToken: tokenData.pushToken
                )
                // Appended so it sends after any queued old-company requests; persisted
                // synchronously so it survives a crash before the first flush.
                QueueStore.shared.enqueue(request, persist: .synchronous)
            }
            // NOTE: do NOT clear the push token here — the switch must preserve it so the
            // token can be re-registered under the new company immediately below.
            if featureFlags.enableCompanySwitchReset {
                // iOS behavior: give the new company a clean identity (fresh anon, PII dropped).
                IdentityStore.shared.update(
                    ProfileData(anonymousId: IdentityStore.shared.mintNewAnonymousId()))
            }
            // Parity (flag OFF): retain the persisted device-scoped identity (PII + anon) as-is.

            // Re-register the preserved token under the new company.
            if let tokenData = IdentityStore.shared.pushToken,
               let newAnon = IdentityStore.shared.current.anonymousId {
                let profile: ProfilePayload = featureFlags.enableCompanySwitchReset
                    ? ProfilePayload(email: nil, phoneNumber: nil, externalId: nil, anonymousId: newAnon)
                    : RequestBuilding.profilePayload(
                        from: Profile(), identity: IdentityStore.shared.current, anonymousId: newAnon
                    )
                let request = RequestFactory.tokenRequest(
                    apiKey: apiKey,
                    pushToken: tokenData.pushToken,
                    enablement: tokenData.pushEnablement,
                    background: tokenData.pushBackground.rawValue,
                    profile: profile
                )
                QueueStore.shared.enqueue(request)
            }
        }

        // ── Branch 3: FALL-THROUGH — normal cold-start init ──────────────────────────────────────
        // Install the incoming key BEFORE `beginInitializing()` flips `SessionState` — otherwise a
        // concurrent enqueue could observe the initialized session while `SDKConfigStore` still holds
        // the prior launch's key and route under the wrong company. Until the session flips, `route`
        // buffers/drops, so the pre-flip window is safe.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        guard LifecycleState.shared.beginInitializing() else { return }
        // Migrate synchronously, before any identity read can hydrate a fresh anonymousId over the
        // persisted identity (and before a racing host setter could be clobbered by the migration).
        migrateLegacyStateIfNeeded(apiKey: apiKey)
        Task { await completeInitialization(apiKey: apiKey) }
    }

    // MARK: - completeInitialization (async tail)

    /// Drains the buffer, transitions to `.initialized`, and starts the lifecycle loop. `@MainActor`
    /// so the transition (and its `@_spi` emit) stay on the main funnel; migration already ran in the
    /// synchronous head of `initialize`.
    @MainActor
    static func completeInitialization(apiKey: String) async {
        // Idempotency: drain + transition + lifecycle run exactly once even if two callers race here.
        guard LifecycleState.shared.current == .initializing else { return }
        RequestEnqueuer.drainBuffer(apiKey: apiKey)
        guard LifecycleState.shared.completeInitialization() else { return }
        await runLifecycle()
    }

    // MARK: - runLifecycle (long-lived lifecycle loop)

    /// Drives the Core `RequestQueue` actor for the lifetime of the SDK session. `@MainActor` so
    /// `setPushEnablement` rejoins the main funnel and can't race host identity/token writes.
    @MainActor
    private static func runLifecycle() async {
        @Sendable
        func handleForeground() async {
            await klaviyoSwiftEnvironment.requestQueue.start()
            let settings = await environment.getNotificationSettings()
            // Direct call instead of `send(.setPushEnablement(settings))`.
            setPushEnablement(settings)
            let autoclearing = await environment.getBadgeAutoClearingSetting()
            if autoclearing {
                await BadgeManager.setBadgeCount(0)
            } else {
                await MainActor.run { BadgeManager.syncBadgeCount() }
            }
        }

        @Sendable
        func handleBackground() async {
            await klaviyoSwiftEnvironment.requestQueue.stop()
            await MainActor.run { BadgeManager.syncBadgeCount() }
        }

        // Launch kickoff — start the queue and sync push enablement immediately on init.
        await handleForeground()
        for await event in environment.lifecycleEventsWithReachability().lifecycleEventStream() {
            switch event {
            case .foregrounded:
                await handleForeground()
            case .backgrounded, .terminated:
                await handleBackground()
            case let .reachabilityChanged(status):
                await klaviyoSwiftEnvironment.requestQueue.networkConnectivityChanged(status)
            }
        }
    }
}
