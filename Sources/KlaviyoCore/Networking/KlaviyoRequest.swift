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

    /// Converts this Klaviyo request into a URLRequest with proper attempt tracking headers.
    ///
    /// This method adds an attempt count header to the request, which helps the Klaviyo API
    /// understand the request's retry status and can influence rate limiting behavior.
    ///
    /// - Parameter attemptInfo: Information about the current attempt and maximum attempts allowed.
    /// - Returns: A URLRequest configured with the appropriate headers and endpoint information.
    /// - Throws: An error if the request cannot be created, either from the endpoint or if
    ///           the provided attemptInfo is invalid.
    public func urlRequest(attemptInfo: RequestAttemptInfo) throws -> URLRequest {
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
        request.setValue("\(attemptInfo.attemptNumber)/\(attemptInfo.maxAttempts)", forHTTPHeaderField: "X-Klaviyo-Attempt-Count")

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
