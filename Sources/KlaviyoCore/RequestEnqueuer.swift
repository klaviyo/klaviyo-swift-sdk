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
/// No reducer routing. See MAGE-951; caller cutover is MAGE-952.
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

    /// The single routing rule: apiKey present → build a request and enqueue it to `QueueStore`;
    /// apiKey absent → append the apiKey-free payload to the `UnattributedBuffer`. The queue is
    /// resolved from the *captured* apiKey (`store(for:)`, not `current()`), so a concurrent
    /// `SDKConfigStore` change can't route the request to another key's queue or drop it.
    private static func route(
        buffered: UnattributedRequest,
        build: (_ apiKey: String) -> KlaviyoRequest
    ) {
        if let apiKey = SDKConfigStore.shared.current.apiKey {
            QueueStore.store(for: apiKey).enqueue(build(apiKey))
        } else {
            UnattributedBuffer.shared.append(buffered)
        }
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
    /// payload already embeds identifiers + anonymousId; routing is the same as every other request:
    /// apiKey present → `QueueStore`, absent → durable `UnattributedBuffer`.
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

    /// Shape A parity: the caller supplies a prebuilt `PushTokenPayload` embedding the profile,
    /// so a pre-init identity change rebinds the token to the new identity in one buffered
    /// request (mirrors the initialized `tokenRequest` path). Routing matches every other entry
    /// point: apiKey present → `QueueStore`, absent → durable `UnattributedBuffer`. (MAGE-1165)
    public static func enqueuePushToken(payload: PushTokenPayload) {
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
    /// removes only the drained FIFO prefix. At-least-once: the final enqueue persists synchronously
    /// so the queue is durable before the buffer is trimmed. A crash in the gap re-drains next launch
    /// (a dedup-able duplicate, never silent loss). Removing the exact drained prefix — rather than
    /// clearing wholesale — means a request appended concurrently during the drain survives instead
    /// of being wiped. Built + tested here; called by the slimmed `initialize(apiKey:)` in MAGE-952.
    ///
    /// - Precondition: `apiKey` must equal `SDKConfigStore.shared.current.apiKey` — the key
    ///   `QueueStore.current()` resolves. If they diverge the drain is skipped to prevent
    ///   requests being stamped with one key but written into another key's queue file.
    public static func drainBuffer(apiKey: String) {
        if apiKey != SDKConfigStore.shared.current.apiKey {
            environment.emitDeveloperWarning(
                "RequestEnqueuer.drainBuffer: apiKey does not match the active SDKConfigStore " +
                    "apiKey; skipping drain to prevent key mismatch in QueueStore"
            )
            return
        }
        let (buffered, cursor) = UnattributedBuffer.shared.drainSnapshot()
        guard !buffered.isEmpty else { return }
        // Resolve the queue from the validated `apiKey` (not `current()`) so a concurrent config
        // change between the guard above and here can't misroute the drained requests.
        let queue = QueueStore.store(for: apiKey)

        for (index, request) in buffered.enumerated() {
            let isLast = index == buffered.count - 1
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
