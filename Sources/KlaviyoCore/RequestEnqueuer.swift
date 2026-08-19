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
        guard let anonymousId = IdentityStore.shared.current.anonymousId else {
            environment.emitDeveloperWarning("RequestEnqueuer: missing anonymousId")
            return
        }
        let identity = IdentityStore.shared.current
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
        guard let anonymousId = IdentityStore.shared.current.anonymousId else {
            environment.emitDeveloperWarning("RequestEnqueuer: missing anonymousId")
            return
        }
        let identity = IdentityStore.shared.current
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
        guard let anonymousId = IdentityStore.shared.current.anonymousId else {
            environment.emitDeveloperWarning("RequestEnqueuer: missing anonymousId")
            return
        }
        let identity = IdentityStore.shared.current
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
}
