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
    public static func enqueueEvent(_ event: Event) {
        let identity = IdentityStore.shared.current
        // Defensive: IdentityStore mints anonymousId on first access (MAGE-894), so this
        // branch is unreachable in practice. Retained against future minting-policy changes.
        guard let anonymousId = identity.anonymousId else {
            environment.emitDeveloperWarning("RequestEnqueuer: missing anonymousId")
            return
        }
        let pushToken = IdentityStore.shared.pushToken?.pushToken
        let payload = RequestFactory.eventPayload(
            anonymousId: anonymousId, email: identity.email,
            phoneNumber: identity.phoneNumber, externalId: identity.externalId,
            event: event, pushToken: pushToken
        )

        if let apiKey = SDKConfigStore.shared.current.apiKey {
            QueueStore.current()?.enqueue(
                KlaviyoRequest(endpoint: .createEvent(apiKey, payload), priority: event.priority))
        } else {
            UnattributedBuffer.shared.append(.event(payload, event.priority))
        }
    }

    public static func enqueueAggregateEvent(_ payload: Data) {
        if let apiKey = SDKConfigStore.shared.current.apiKey {
            QueueStore.current()?.enqueue(
                KlaviyoRequest(endpoint: .aggregateEvent(apiKey, payload)))
        } else {
            UnattributedBuffer.shared.append(.aggregateEvent(payload))
        }
    }

    public static func enqueueProfile(properties: [String: Any]) {
        let identity = IdentityStore.shared.current
        // Defensive: see enqueueEvent comment — unreachable under current minting policy.
        guard let anonymousId = identity.anonymousId else {
            environment.emitDeveloperWarning("RequestEnqueuer: missing anonymousId")
            return
        }
        let payload = RequestFactory.profilePayload(
            anonymousId: anonymousId, email: identity.email,
            phoneNumber: identity.phoneNumber, externalId: identity.externalId,
            properties: properties
        )

        if let apiKey = SDKConfigStore.shared.current.apiKey {
            QueueStore.current()?.enqueue(
                KlaviyoRequest(endpoint: .createProfile(apiKey, payload)))
        } else {
            UnattributedBuffer.shared.append(.profile(payload))
        }
    }

    public static func enqueuePushToken(_ token: String, enablement: PushEnablement) {
        let identity = IdentityStore.shared.current
        // Defensive: see enqueueEvent comment — unreachable under current minting policy.
        guard let anonymousId = identity.anonymousId else {
            environment.emitDeveloperWarning("RequestEnqueuer: missing anonymousId")
            return
        }
        let payload = RequestFactory.tokenPayload(
            anonymousId: anonymousId, email: identity.email,
            phoneNumber: identity.phoneNumber, externalId: identity.externalId,
            pushToken: token, enablement: enablement,
            background: environment.getBackgroundSetting().rawValue
        )

        if let apiKey = SDKConfigStore.shared.current.apiKey {
            QueueStore.current()?.enqueue(
                KlaviyoRequest(endpoint: .registerPushToken(apiKey, payload)))
        } else {
            UnattributedBuffer.shared.append(.pushToken(payload))
        }
    }

    /// Moves every buffered request into `QueueStore`, stamping `apiKey` into each endpoint, then
    /// clears the buffer. At-least-once: the final enqueue persists synchronously so the queue is
    /// durable before the buffer file is removed. A crash in the gap re-drains next launch (a
    /// dedup-able duplicate, never silent loss). Built + tested here; called by MAGE-952's
    /// slimmed `initialize(apiKey:)`.
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
        let buffered = UnattributedBuffer.shared.snapshot()
        guard !buffered.isEmpty, let queue = QueueStore.current() else { return }

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
        UnattributedBuffer.shared.clear()
    }
}
