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
            throw KlaviyoAPIError.internalError("Invalid url string. API URL: \(environment.apiURL())")
        }
        var request = URLRequest(url: url)
        // We only support post right now
        guard let body = try? endpoint.body() else {
            throw KlaviyoAPIError.dataEncodingError(self)
        }
        request.httpBody = body
        request.httpMethod = endpoint.httpMethod.rawValue
        request.setValue("\(attemptNumber)/50", forHTTPHeaderField: "X-Klaviyo-Attempt-Count")

        return request
    }

    var url: URL? {
        guard !environment.apiURL().isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = endpoint.httpScheme
        components.host = environment.apiURL()
        components.path = endpoint.path
        components.queryItems = [
            URLQueryItem(name: "company_id", value: apiKey)
        ]

        return components.url
    }
}
