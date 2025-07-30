//
//  KlaviyoRequest.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation

/// A request that can be sent to the Klaviyo API.
///
/// This struct encapsulates all the information needed to make a request to Klaviyo's API,
/// including the endpoint to call and a unique identifier for tracking the request.
public struct KlaviyoRequest: Identifiable, Equatable, Codable {
    /// A unique identifier for the request.
    public let id: String

    /// The API key (a.k.a. "Company ID") to use for the request.
    private let apiKey: String

    /// The API endpoint this request targets.
    public let endpoint: KlaviyoEndpoint

    /// Creates a new request to the Klaviyo API.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this request. If not provided, a UUID will be generated.
    ///   - apiKey: The API key (a.k.a. "Company ID") to use for the request.
    ///   - endpoint: The endpoint this request will target.
    public init(
        id: String = environment.uuid().uuidString,
        apiKey: String,
        endpoint: KlaviyoEndpoint
    ) {
        self.id = id
        self.apiKey = apiKey
        self.endpoint = endpoint
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
