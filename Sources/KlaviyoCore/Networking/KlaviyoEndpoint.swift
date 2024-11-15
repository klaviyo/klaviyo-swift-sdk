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

public enum KlaviyoEndpoint: Equatable, Codable {
    case createProfile(CreateProfilePayload)
    case createEvent(CreateEventPayload)
    case registerPushToken(PushTokenPayload)
    case unregisterPushToken(UnregisterPushTokenPayload)
}
