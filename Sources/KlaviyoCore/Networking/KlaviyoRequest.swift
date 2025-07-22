//
//  KlaviyoRequest.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation

public struct KlaviyoRequest: Equatable, Codable {
    private let apiKey: String
    public let endpoint: KlaviyoEndpoint
    public var uuid: String

    public init(
        apiKey: String,
        endpoint: KlaviyoEndpoint,
        uuid: String = environment.uuid().uuidString
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.uuid = uuid
    }

    public func urlRequest(currentAttempt: Int = 1, maxAttempts: Int) throws -> URLRequest {
        guard let url = url else {
            throw KlaviyoAPIError.internalError("Invalid url string. API URL: \(environment.apiURL())")
        }

        var request = URLRequest(url: url)

        do {
            if let body = try endpoint.body(), !body.isEmpty {
                request.httpBody = body
            }
        } catch {
            throw KlaviyoAPIError.dataEncodingError(self)
        }

        request.httpMethod = endpoint.httpMethod.rawValue
        request.setValue("\(currentAttempt)/\(maxAttempts)", forHTTPHeaderField: "X-Klaviyo-Attempt-Count")

        return request
    }

    var url: URL? {
        var urlComponents = environment.apiURL()

        guard urlComponents.scheme != nil, urlComponents.host != nil else {
            return nil
        }

        urlComponents.path = endpoint.path
        urlComponents.queryItems = [
            URLQueryItem(name: "company_id", value: apiKey)
        ]

        return urlComponents.url
    }
}
