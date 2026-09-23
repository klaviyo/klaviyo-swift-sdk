//
//  RequestEnqueuer.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/26.
//

import Foundation

/// Ungated Core enqueue entry point. Reads identity + apiKey from the shared stores itself,
/// so callers never thread identity or check for an apiKey. apiKey present → build + enqueue
/// to `QueueStore`; apiKey absent → build an apiKey-free payload → `UnattributedBuffer`.
/// Routes pre-init calls to `UnattributedBuffer`; post-init calls to `QueueStore`.
public enum RequestEnqueuer {
    static let missingAnonymousIdWarning = "RequestEnqueuer: missing anonymousId"

    /// Resolves the current identity, or emits a warning and returns `nil`. `anonymousId` is minted
    /// on first access under the current single-minter policy, so `nil` is defensive and
    /// unreachable in practice — retained against future minting-policy changes.
    private static func resolveIdentity() -> PayloadIdentity? {
        let identity = IdentityStore.shared.current
        guard let anonymousId = identity.anonymousId else {
            environment.emitDeveloperWarning(missingAnonymousIdWarning)
            return nil
        }
        return PayloadIdentity(
            anonymousId: anonymousId, email: identity.email,
            phoneNumber: identity.phoneNumber, externalId: identity.externalId
        )
    }

    /// Routes a request based on `SessionState.isInitialized` (whether `initialize()` has started this
    /// process):
    ///
    /// - Post-init → build a request and enqueue directly to `QueueStore` (`apiKey` is set by the time
    ///   the session is marked).
    /// - Pre-init + `enablePreInitDiskCapture` ON → append to the durable `UnattributedBuffer`.
    /// - Pre-init + `enablePreInitDiskCapture` OFF → hold a high-priority event (push-open) in the
    ///   non-durable `PreInitMemoryBuffer`; drop everything else with a developer warning.
    private static func route(
        buffered: UnattributedRequest,
        build: (_ apiKey: String) -> KlaviyoRequest
    ) {
        if SessionState.isInitialized, let apiKey = SDKConfigStore.shared.current.apiKey {
            QueueStore.shared.enqueue(build(apiKey))
        } else if featureFlags.enablePreInitDiskCapture {
            UnattributedBuffer.shared.append(buffered)
        } else if isHighPriorityEvent(buffered) {
            // Android parity: hold pre-init push-opens in a non-durable in-memory buffer; drop the
            // rest (Android drops all pre-init calls except in-memory push-opens).
            PreInitMemoryBuffer.shared.append(buffered)
        } else {
            environment.emitDeveloperWarning(
                "Klaviyo SDK not initialized; dropping pre-init request")
        }
    }

    /// A buffered request is a high-priority push-open iff it is a `.high`-priority event. On this
    /// branch the only `.high` events are Klaviyo-prioritized events (`$opened_push`), mirroring
    /// Android's `isKlaviyoMetric` high-priority lane.
    private static func isHighPriorityEvent(_ request: UnattributedRequest) -> Bool {
        if case let .event(_, priority) = request { return priority == .high }
        return false
    }

    public static func enqueueEvent(_ event: Event) {
        guard let identity = resolveIdentity() else { return }
        let pushToken = IdentityStore.shared.pushToken?.pushToken
        let payload = RequestFactory.eventPayload(identity: identity, event: event, pushToken: pushToken)
        route(buffered: .event(payload, event.priority)) { apiKey in
            KlaviyoRequest(endpoint: .createEvent(apiKey, payload), priority: event.priority)
        }
    }

    public static func enqueueAggregateEvent(_ payload: Data) {
        route(buffered: .aggregateEvent(payload)) { apiKey in
            KlaviyoRequest(endpoint: .aggregateEvent(apiKey, payload))
        }
    }

    /// Enqueues an already-built `CreateProfilePayload`. Unlike the other entry points, the caller
    /// supplies the full payload — profiles carry structured attributes (firstName/lastName/title/
    /// organization/image/location) that only the KlaviyoSwift `Profile` → `ProfilePayload` mapping
    /// can populate, so building here (with just identity + flat properties) would drop them. The
    /// payload already embeds identifiers + anonymousId; routing is the same as every other request
    /// (see `route`).
    public static func enqueueProfile(payload: CreateProfilePayload) {
        route(buffered: .profile(payload)) { apiKey in
            KlaviyoRequest(endpoint: .createProfile(apiKey, payload))
        }
    }

    public static func enqueuePushToken(_ token: String, enablement: PushEnablement) {
        guard let identity = resolveIdentity() else { return }
        let payload = RequestFactory.tokenPayload(
            identity: identity, pushToken: token, enablement: enablement,
            background: environment.getBackgroundSetting()
        )
        route(buffered: .pushToken(payload)) { apiKey in
            KlaviyoRequest(endpoint: .registerPushToken(apiKey, payload))
        }
    }

    /// Enqueues a `registerPushToken` carrying a FULL profile (attributes + properties), used by the
    /// Android-parity fold path where a profile update rides on the token request instead of a
    /// separate createProfile. Routes buffer/queue like the identity-only overload.
    public static func enqueuePushToken(
        token: String,
        enablement: PushEnablement,
        profile: ProfilePayload
    ) {
        let payload = RequestFactory.tokenPayload(
            pushToken: token,
            enablement: enablement,
            background: environment.getBackgroundSetting(),
            profile: profile
        )
        route(buffered: .pushToken(payload)) { apiKey in
            KlaviyoRequest(endpoint: .registerPushToken(apiKey, payload))
        }
    }

    /// Mirrors `enqueueProfile`: the caller supplies the built payload (channel validation lives in
    /// the KlaviyoSwift `Subscription` → payload mapping).
    public static func enqueueSubscription(payload: CreateSubscriptionPayload) {
        route(buffered: .subscription(payload)) { apiKey in
            KlaviyoRequest(endpoint: .createSubscription(apiKey, payload))
        }
    }

    /// The `logTrackingLinkClicked` endpoint is apiKey-free, so the `build` closure ignores `apiKey`
    /// (routing still keys the target `QueueStore` on it). Identity is resolved here, like `enqueueEvent`.
    public static func enqueueTrackingLinkClicked(trackingLink: URL, clickTime: Date) {
        guard let identity = resolveIdentity() else { return }
        let profileInfo = ProfilePayload(
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            anonymousId: identity.anonymousId
        )
        route(
            buffered: .trackingLinkClick(
                trackingLink: trackingLink, clickTime: clickTime, profileInfo: profileInfo
            )
        ) { _ in
            KlaviyoRequest(endpoint: .logTrackingLinkClicked(
                trackingLink: trackingLink, clickTime: clickTime, profileInfo: profileInfo
            ))
        }
    }

    /// Moves every buffered request into `QueueStore`, stamping `apiKey` into each endpoint, then
    /// removes only the drained FIFO prefix from the durable buffer. Drains BOTH the durable disk
    /// buffer (`UnattributedBuffer`) and the non-durable in-memory buffer (`PreInitMemoryBuffer`);
    /// in each operating mode one is empty, so draining both is always safe.
    ///
    /// At-least-once: the final enqueue persists synchronously so the queue is durable before the
    /// disk buffer is trimmed. A crash in the gap re-drains next launch (a dedup-able duplicate,
    /// never silent loss). Removing the exact drained prefix — rather than clearing wholesale — means
    /// a request appended concurrently during the drain survives instead of being wiped.
    ///
    /// - Precondition: `apiKey` must equal `SDKConfigStore.shared.current.apiKey`. If they diverge
    ///   the drain is skipped so buffered requests aren't stamped with a key that no longer matches
    ///   the active config.
    public static func drainBuffer(apiKey: String) {
        if apiKey != SDKConfigStore.shared.current.apiKey {
            environment.emitDeveloperWarning(
                "RequestEnqueuer.drainBuffer: apiKey does not match the active SDKConfigStore " +
                    "apiKey; skipping drain to prevent key mismatch in QueueStore"
            )
            return
        }

        let queue = QueueStore.shared

        // Durable disk buffer (populated when enablePreInitDiskCapture is on).
        let (buffered, cursor) = UnattributedBuffer.shared.drainSnapshot()
        // Non-durable in-memory buffer (populated in Android-parity mode).
        let memory = PreInitMemoryBuffer.shared.drain()

        let all = buffered + memory
        guard !all.isEmpty else { return }

        for (index, request) in all.enumerated() {
            let isLast = index == all.count - 1
            let policy: PersistPolicy = isLast ? .synchronous : .debounced
            switch request {
            case let .event(payload, priority):
                queue.enqueue(
                    KlaviyoRequest(endpoint: .createEvent(apiKey, payload), priority: priority),
                    persist: policy
                )
            case let .aggregateEvent(payload):
                queue.enqueue(
                    KlaviyoRequest(endpoint: .aggregateEvent(apiKey, payload)), persist: policy
                )
            case let .profile(payload):
                queue.enqueue(
                    KlaviyoRequest(endpoint: .createProfile(apiKey, payload)), persist: policy
                )
            case let .pushToken(payload):
                queue.enqueue(
                    KlaviyoRequest(endpoint: .registerPushToken(apiKey, payload)), persist: policy
                )
            case let .trackingLinkClick(trackingLink, clickTime, profileInfo):
                queue.enqueue(
                    KlaviyoRequest(endpoint: .logTrackingLinkClicked(
                        trackingLink: trackingLink, clickTime: clickTime, profileInfo: profileInfo
                    )), persist: policy
                )
            case let .subscription(payload):
                queue.enqueue(
                    KlaviyoRequest(endpoint: .createSubscription(apiKey, payload)), persist: policy
                )
            }
        }
        UnattributedBuffer.shared.removeDrained(throughCursor: cursor)
    }
}
