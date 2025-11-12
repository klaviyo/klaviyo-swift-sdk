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
public struct KlaviyoRequest: Identifiable, Equatable, Codable, Sendable {
    /// A unique identifier for the request.
    public let id: String

    /// The API endpoint this request targets.
    public let endpoint: KlaviyoEndpoint

    /// Creates a new request to the Klaviyo API.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this request. If not provided, a UUID will be generated.
    ///   - endpoint: The endpoint this request will target.
    public init(
        id: String = environment.uuid().uuidString,
        endpoint: KlaviyoEndpoint
    ) {
        self.id = id
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
        var request = try endpoint.urlRequest()
        request.setValue("\(attemptInfo.attemptNumber)/\(attemptInfo.maxAttempts)", forHTTPHeaderField: "X-Klaviyo-Attempt-Count")
        return request
    }
}
