//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import AnyCodable
import Foundation

public struct KlaviyoRequest: Equatable, Codable {
    public init(
        apiKey: String,
        endpoint: KlaviyoEndpoint,
        uuid: String = analytics.uuid().uuidString) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.uuid = uuid
    }

    public let apiKey: String
    public let endpoint: KlaviyoEndpoint
    public var uuid = analytics.uuid().uuidString

    public func urlRequest(_ attemptNumber: Int = 1) throws -> URLRequest {
        guard let url = url else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("Invalid url string. API URL: \(analytics.apiURL)")
        }
        var request = URLRequest(url: url)
        // We only support post right now
        guard let body = try? encodeBody() else {
            throw KlaviyoAPI.KlaviyoAPIError.dataEncodingError(self)
        }
        request.httpBody = body
        request.httpMethod = "POST"
        request.setValue("\(attemptNumber)/50", forHTTPHeaderField: "X-Klaviyo-Attempt-Count")

        return request
    }

    var url: URL? {
        switch endpoint {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken:
            if !analytics.apiURL.isEmpty {
                return URL(string: "\(analytics.apiURL)/\(path)/?company_id=\(apiKey)")
            }
            return nil
        }
    }

    var path: String {
        switch endpoint {
        case .createProfile:
            return "client/profiles"

        case .createEvent:
            return "client/events"

        case .registerPushToken:
            return "client/push-tokens"

        case .unregisterPushToken:
            return "client/push-token-unregister"
        }
    }

    func encodeBody() throws -> Data {
        switch endpoint {
        case let .createProfile(payload):
            return try analytics.encodeJSON(AnyEncodable(payload))

        case var .createEvent(payload):
            payload.appendMetadataToProperties()
            return try analytics.encodeJSON(AnyEncodable(payload))

        case let .registerPushToken(payload):
            return try analytics.encodeJSON(AnyEncodable(payload))

        case let .unregisterPushToken(payload):
            return try analytics.encodeJSON(AnyEncodable(payload))
        }
    }
}
