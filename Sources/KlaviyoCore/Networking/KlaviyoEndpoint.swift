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

    public var headers: [String: String] { [:] }

    public var queryItems: [URLQueryItem] { [] }

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

extension KlaviyoEndpoint {
    public func urlRequest() throws -> URLRequest {
        let baseURL = try baseURL()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            let message = "Failed to build URL components from base URL '\(baseURL)'"
            if #available(iOS 14.0, *) {
                Logger.networking.warning("\(message)")
            }
            throw KlaviyoAPIError.internalError(message)
        }

        let validatedPath = path
        if !validatedPath.isEmpty && !validatedPath.hasPrefix("/") {
            let message = "Path does not begin with '/': '\(validatedPath)'. Paths should start with a forward slash."
            if #available(iOS 14.0, *) {
                Logger.networking.warning("\(message)")
            }
            throw KlaviyoAPIError.internalError(message)
        }

        components.path = validatedPath

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            let message = "Failed to build valid URL from components: \(components)"
            if #available(iOS 14.0, *) {
                Logger.networking.warning("\(message)")
            }
            throw KlaviyoAPIError.internalError(message)
        }

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod.rawValue
        request.allHTTPHeaderFields = headers

        if let body = try body(), !body.isEmpty {
            request.httpBody = body
        }

        return request
    }
}
