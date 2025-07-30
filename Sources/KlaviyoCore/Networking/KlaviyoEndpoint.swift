//
//  KlaviyoEndpoint.swift
//  Internal models typically used at the networking layer.
//  NOTE: Ensure that new request types are equatable and encodable.
//
//  Created by Noah Durell on 11/25/22.
//

import Foundation
import OSLog

public enum KlaviyoEndpoint: Equatable, Codable {
    case createProfile(CreateProfilePayload)
    case createEvent(CreateEventPayload)
    case registerPushToken(PushTokenPayload)
    case unregisterPushToken(UnregisterPushTokenPayload)
    case aggregateEvent(AggregateEventPayload)

    var httpMethod: RequestMethod {
        switch self {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken, .aggregateEvent:
            return .post
        }
    }

    public func baseURL() throws -> URL {
        guard environment.apiURL().scheme != nil,
              environment.apiURL().host != nil,
              let url = environment.apiURL().url else {
            let errorMessage = (environment.apiURL().scheme == nil || environment.apiURL().host == nil)
                ?
                "Failed to build valid URL; scheme and/or host is nil"
                :
                "Failed to build valid URL from base components '\(String(describing: environment.apiURL()))'"

            if #available(iOS 14.0, *) {
                Logger.networking.warning("\(errorMessage)")
            }
            throw KlaviyoAPIError.internalError("\(errorMessage)")
        }

        return url
    }

    var path: String {
        switch self {
        case .createProfile:
            return "/client/profiles/"
        case .createEvent:
            return "/client/events/"
        case .registerPushToken:
            return "/client/push-tokens/"
        case .unregisterPushToken:
            return "/client/push-token-unregister/"
        case .aggregateEvent:
            return "/onsite/track-analytics"
        }
    }

    func body() throws -> Data? {
        switch self {
        case let .createProfile(payload):
            return try environment.encodeJSON(payload)
        case let .createEvent(payload):
            return try environment.encodeJSON(payload)
        case let .registerPushToken(payload):
            return try environment.encodeJSON(payload)
        case let .unregisterPushToken(payload):
            return try environment.encodeJSON(payload)
        case let .aggregateEvent(payload):
            return payload
        }
    }
}
