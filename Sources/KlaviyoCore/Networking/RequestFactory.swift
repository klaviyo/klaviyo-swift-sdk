//
//  RequestFactory.swift
//
//  Klaviyo Swift SDK
//
//  Created by Belle Lim on 7/23/26.
//

import AnyCodable
import Foundation

/// Identity inputs required to construct a Klaviyo API request.
///
/// Supplied by the caller (today: the reducer / `KlaviyoState`; later: `IdentityStore`).
public struct RequestIdentity: Equatable {
    public let apiKey: String
    public let anonymousId: String
    public let email: String?
    public let phoneNumber: String?
    public let externalId: String?

    public init(apiKey: String,
                anonymousId: String,
                email: String? = nil,
                phoneNumber: String? = nil,
                externalId: String? = nil) {
        self.apiKey = apiKey
        self.anonymousId = anonymousId
        self.email = email
        self.phoneNumber = phoneNumber
        self.externalId = externalId
    }
}

/// Pure construction of `KlaviyoRequest` values from domain inputs.
///
/// Reads no store and does not touch `environment`. Byte-identical to the
/// construction previously inlined in `KlaviyoState` / the reducer.
public enum RequestFactory {
    public static func profileRequest(
        identity: RequestIdentity,
        properties: [String: Any] = [:]
    ) -> KlaviyoRequest {
        profileRequest(apiKey: identity.apiKey,
                       payload: profilePayload(identity: identity, properties: properties))
    }

    /// Builds a `CreateProfilePayload` from identity + properties without wrapping it in a request,
    /// so callers can resolve/merge it (e.g. a pending-profile merge) before turning it into a
    /// request via ``profileRequest(apiKey:payload:)``.
    public static func profilePayload(
        identity: RequestIdentity,
        properties: [String: Any] = [:]
    ) -> CreateProfilePayload {
        CreateProfilePayload(data: ProfilePayload(
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            properties: properties,
            anonymousId: identity.anonymousId
        ))
    }

    /// Wraps an already-resolved `CreateProfilePayload` (e.g. after a pending-profile merge).
    public static func profileRequest(
        apiKey: String,
        payload: CreateProfilePayload
    ) -> KlaviyoRequest {
        KlaviyoRequest(endpoint: .createProfile(apiKey, payload))
    }

    public static func eventRequest(
        identity: RequestIdentity,
        event: Event,
        pushToken: String?
    ) -> KlaviyoRequest {
        let stamped = event.updateEventWithIdentifiers(
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            pushToken: pushToken
        )
        let payload = CreateEventPayload(
            data: CreateEventPayload.Event(
                name: stamped.metric.name.value,
                properties: stamped.properties,
                email: stamped.identifiers?.email,
                phoneNumber: stamped.identifiers?.phoneNumber,
                externalId: stamped.identifiers?.externalId,
                anonymousId: identity.anonymousId,
                value: stamped.value,
                time: stamped.time,
                uniqueId: stamped.uniqueId,
                pushToken: pushToken
            ))
        return KlaviyoRequest(endpoint: .createEvent(identity.apiKey, payload), priority: stamped.priority)
    }

    public static func unregisterRequest(
        identity: RequestIdentity,
        pushToken: String
    ) -> KlaviyoRequest {
        let payload = UnregisterPushTokenPayload(
            pushToken: pushToken,
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            anonymousId: identity.anonymousId
        )
        return KlaviyoRequest(endpoint: .unregisterPushToken(identity.apiKey, payload))
    }

    public static func tokenRequest(
        apiKey: String,
        pushToken: String,
        enablement: PushEnablement,
        background: String,
        profile: ProfilePayload
    ) -> KlaviyoRequest {
        let payload = PushTokenPayload(
            pushToken: pushToken,
            enablement: enablement.rawValue,
            background: background,
            profile: profile
        )
        return KlaviyoRequest(endpoint: .registerPushToken(apiKey, payload))
    }
}
