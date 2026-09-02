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

    public init(
        apiKey: String,
        anonymousId: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil
    ) {
        self.apiKey = apiKey
        self.anonymousId = anonymousId
        self.email = email
        self.phoneNumber = phoneNumber
        self.externalId = externalId
    }
}

/// apiKey-free identity fields needed to build a request *payload*. Unlike ``RequestIdentity``
/// it carries no apiKey, so it is usable before `initialize()` (e.g. the pre-apiKey buffer path).
public struct PayloadIdentity: Equatable {
    public let anonymousId: String
    public let email: String?
    public let phoneNumber: String?
    public let externalId: String?

    public init(
        anonymousId: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil
    ) {
        self.anonymousId = anonymousId
        self.email = email
        self.phoneNumber = phoneNumber
        self.externalId = externalId
    }

    /// Drops the apiKey from a ``RequestIdentity``.
    public init(_ identity: RequestIdentity) {
        self.init(
            anonymousId: identity.anonymousId,
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId
        )
    }
}

/// Pure construction of `KlaviyoRequest` values from domain inputs.
public enum RequestFactory {
    public static func profileRequest(
        identity: RequestIdentity,
        properties: [String: Any] = [:]
    ) -> KlaviyoRequest {
        profileRequest(
            apiKey: identity.apiKey,
            payload: profilePayload(identity: identity, properties: properties)
        )
    }

    /// Builds a `CreateProfilePayload` from identity + properties without wrapping it in a request,
    /// so callers can resolve/merge it (e.g. a pending-profile merge) before turning it into a
    /// request via ``profileRequest(apiKey:payload:)``.
    public static func profilePayload(
        identity: RequestIdentity,
        properties: [String: Any] = [:]
    ) -> CreateProfilePayload {
        profilePayload(identity: PayloadIdentity(identity), properties: properties)
    }

    /// Builds a `CreateProfilePayload` from apiKey-free identity fields.
    ///
    /// Use this when a profile payload must be constructed before an apiKey is available,
    /// e.g. in the pre-apiKey buffer path.
    public static func profilePayload(
        identity: PayloadIdentity,
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
        let payload = eventPayload(identity: PayloadIdentity(identity), event: event, pushToken: pushToken)
        return KlaviyoRequest(endpoint: .createEvent(identity.apiKey, payload), priority: event.priority)
    }

    /// Builds a `CreateEventPayload` from apiKey-free identity fields.
    ///
    /// Use this when an event payload must be constructed before an apiKey is available,
    /// e.g. in the pre-apiKey buffer path.
    public static func eventPayload(
        identity: PayloadIdentity,
        event: Event,
        pushToken: String?
    ) -> CreateEventPayload {
        let stamped = event.updateEventWithIdentifiers(
            email: identity.email,
            phoneNumber: identity.phoneNumber,
            externalId: identity.externalId,
            pushToken: pushToken
        )
        return CreateEventPayload(
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

    /// Builds a `PushTokenPayload` from apiKey-free identity fields.
    ///
    /// Constructs an empty-properties `ProfilePayload` internally, matching how the live
    /// push-token registration path resolves the profile before calling ``tokenRequest``.
    /// Use this when a token payload must be constructed before an apiKey is available,
    /// e.g. in the pre-apiKey buffer path.
    public static func tokenPayload(
        identity: PayloadIdentity,
        pushToken: String,
        enablement: PushEnablement,
        background: PushBackground
    ) -> PushTokenPayload {
        PushTokenPayload(
            pushToken: pushToken,
            enablement: enablement.rawValue,
            background: background.rawValue,
            profile: ProfilePayload(
                email: identity.email,
                phoneNumber: identity.phoneNumber,
                externalId: identity.externalId,
                properties: [:],
                anonymousId: identity.anonymousId
            )
        )
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
