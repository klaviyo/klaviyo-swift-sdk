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
    /// apiKey absent → append the apiKey-free payload to the `UnattributedBuffer`.
    private static func route(
        buffered: UnattributedRequest,
        build: (_ apiKey: String) -> KlaviyoRequest
    ) {
        if let apiKey = SDKConfigStore.shared.current.apiKey {
            QueueStore.current()?.enqueue(build(apiKey))
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

    public static func enqueueProfile(properties: [String: Any]) {
        guard let identity = resolveIdentity() else { return }
        let payload = RequestFactory.profilePayload(identity: identity, properties: properties)
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
        // Defensive: `QueueStore.current()` only returns nil when no apiKey is set, and the mismatch
        // guard above already returns in that case — so this is unreachable today. Retained (and
        // warned) so a future change that can yield a nil queue never drops the buffer silently.
        guard let queue = QueueStore.current() else {
            environment.emitDeveloperWarning(
                "RequestEnqueuer.drainBuffer: no QueueStore for the active apiKey; " +
                    "buffered requests are retained for a later drain"
            )
            return
        }

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
            }
        }
        UnattributedBuffer.shared.removeDrained(throughCursor: cursor)
    }
}
