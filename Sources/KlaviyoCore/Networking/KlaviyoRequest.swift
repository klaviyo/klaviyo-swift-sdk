//
//  KlaviyoRequest.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import AnyCodable
import Foundation

public struct KlaviyoRequest: Equatable, Codable {
    public let apiKey: String
    public let endpoint: KlaviyoEndpoint
    public var uuid: String

    public init(
        apiKey: String,
        endpoint: KlaviyoEndpoint,
        uuid: String = environment.uuid().uuidString) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.uuid = uuid
    }

    public func urlRequest(_ attemptNumber: Int = 1) throws -> URLRequest {
        guard let url = url else {
            throw KlaviyoAPIError.internalError("Invalid url string. API URL: \(environment.apiURL)")
        }
        var request = URLRequest(url: url)
        // We only support post right now
        guard let body = try? encodeBody() else {
            throw KlaviyoAPIError.dataEncodingError(self)
        }
        request.httpBody = body
        request.httpMethod = "POST"
        request.setValue("\(attemptNumber)/50", forHTTPHeaderField: "X-Klaviyo-Attempt-Count")

        return request
    }

    var url: URL? {
        switch endpoint {
        case .createProfile, .createEvent, .registerPushToken, .unregisterPushToken:
            if !environment.apiURL.isEmpty {
                return URL(string: "\(environment.apiURL)/\(path)/?company_id=\(apiKey)")
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
