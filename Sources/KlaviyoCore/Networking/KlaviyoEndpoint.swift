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
    case createProfile(_ apiKey: String, _ payload: CreateProfilePayload)
    case createEvent(_ apiKey: String, _ payload: CreateEventPayload)
    case registerPushToken(_ apiKey: String, _ payload: PushTokenPayload)
    case unregisterPushToken(_ apiKey: String, _ payload: UnregisterPushTokenPayload)
    case aggregateEvent(_ apiKey: String, _ payload: AggregateEventPayload)
    case resolveDestinationURL(trackingLink: URL, profileInfo: ProfilePayload)
    case logTrackingLinkClicked(trackingLink: URL, clickTime: Date, profileInfo: ProfilePayload)
    case fetchGeofences(_ apiKey: String, latitude: Double, longitude: Double)

    private enum HeaderKey {
        static let profileInfo = "X-Klaviyo-Profile-Info"
        static let clickEventTimestamp = "X-Klaviyo-Click-Event-Timestamp"
    }

    public var headers: [String: String] {
        switch self {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken, .aggregateEvent, .fetchGeofences:
            return [:]
        case let .resolveDestinationURL(_, profileInfo):
            var dict = [String: String]()
            if let profileInfoString = try? profileInfo.asJSONString() {
                dict[HeaderKey.profileInfo] = profileInfoString
            }
            return dict
        case let .logTrackingLinkClicked(_, timestamp, profileInfo):
            var dict = [String: String]()
            if let profileInfoString = try? profileInfo.asJSONString() {
                dict[HeaderKey.profileInfo] = profileInfoString
            }
            dict[HeaderKey.clickEventTimestamp] = String(Int(timestamp.timeIntervalSince1970))
            return dict
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case let .createProfile(apiKey, _),
             let .createEvent(apiKey, _),
             let .registerPushToken(apiKey, _),
             let .unregisterPushToken(apiKey, _),
             let .aggregateEvent(apiKey, _):
            return [URLQueryItem(name: "company_id", value: apiKey)]
        case let .fetchGeofences(apiKey, latitude, longitude):
            return [
                URLQueryItem(name: "company_id", value: apiKey),
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude))
            ]
        case .resolveDestinationURL, .logTrackingLinkClicked:
            return []
        }
    }

    var httpMethod: HTTPMethod {
        switch self {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken, .aggregateEvent:
            return .post
        case .resolveDestinationURL, .logTrackingLinkClicked, .fetchGeofences:
            return .get
        }
    }

    public func baseURL() throws -> URL {
        switch self {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken, .aggregateEvent, .fetchGeofences:
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
        case let .resolveDestinationURL(trackingLink, _), let .logTrackingLinkClicked(trackingLink, _, _):
            var urlComponents = URLComponents()

            urlComponents.scheme = trackingLink.scheme
            urlComponents.host = trackingLink.host

            guard let url = urlComponents.url else {
                throw KlaviyoAPIError.internalError("Failed to build valid URL from URLComponents '\(urlComponents)'")
            }

            return url
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
        case .aggregateEvent:
            return "/onsite/track-analytics"
        case let .resolveDestinationURL(trackingLink, _), let .logTrackingLinkClicked(trackingLink, _, _):
            return trackingLink.path
        case .fetchGeofences:
            return "/client/geofences"
        }
    }

    func body() throws -> Data? {
        switch self {
        case let .createProfile(_, payload):
            return try environment.encodeJSON(payload)
        case let .createEvent(_, payload):
            return try environment.encodeJSON(payload)
        case let .registerPushToken(_, payload):
            return try environment.encodeJSON(payload)
        case let .unregisterPushToken(_, payload):
            return try environment.encodeJSON(payload)
        case let .aggregateEvent(_, payload):
            return payload
        case .resolveDestinationURL, .logTrackingLinkClicked, .fetchGeofences:
            return nil
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

extension ProfilePayload {
    fileprivate func asJSONString() throws -> String {
        do {
            let profileData = try environment.encodeJSON(self)
            return profileData.base64EncodedString()
        } catch {
            if #available(iOS 14.0, *) {
                Logger.codable.warning("Unable to encode ProfilePayload into JSON string; error: \(error)")
            }
            throw error
        }
    }
}
