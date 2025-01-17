//
//  KlaviyoEndpoint.swift
//  Internal models typically used at the networking layer.
//  NOTE: Ensure that new request types are equatable and encodable.
//
//  Created by Noah Durell on 11/25/22.
//

import AnyCodable
import Foundation

public enum KlaviyoEndpoint: Equatable, Codable {
    case createProfile(CreateProfilePayload)
    case createEvent(CreateEventPayload)
    case registerPushToken(PushTokenPayload)
    case unregisterPushToken(UnregisterPushTokenPayload)
    case fetchForms

    var httpScheme: String { "https" }

    var httpMethod: RequestMethod {
        switch self {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken:
            return .post
        case .fetchForms:
            return .get
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
        case .fetchForms:
            return "/forms/api/v7/full-forms"
        }
    }

    func body() throws -> Data? {
        switch self {
        case let .createProfile(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        case let .createEvent(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        case let .registerPushToken(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        case let .unregisterPushToken(payload):
            return try environment.encodeJSON(AnyEncodable(payload))
        case .fetchForms:
            return nil
        }
    }
}
