//
//  KlaviyoEndpoint.swift
//  Internal models typically used at the networking layer.
//  NOTE: Ensure that new request types are equatable and encodable.
//
//  Created by Noah Durell on 11/25/22.
//

import AnyCodable
import Foundation

protocol Endpoint: Equatable, Codable {
    var httpMethod: RequestMethod { get }
    var path: String { get }

    func body() throws -> Data
}

public enum KlaviyoEndpoint: Endpoint {
    case createProfile(CreateProfilePayload)
    case createEvent(CreateEventPayload)
    case registerPushToken(PushTokenPayload)
    case unregisterPushToken(UnregisterPushTokenPayload)

    var httpMethod: RequestMethod {
        switch self {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken:
            return .post
        }
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
        }
    }

    func body() throws -> Data {
        switch self {
        case let .createProfile(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        case let .createEvent(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        case let .registerPushToken(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        case let .unregisterPushToken(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        }
    }
}
