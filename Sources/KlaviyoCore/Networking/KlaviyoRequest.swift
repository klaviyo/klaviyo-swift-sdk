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

    /// The API endpoint this request targets.
    public let endpoint: KlaviyoEndpoint

    /// The time at which this request was added to the send queue.
    ///
    /// Used to evict the oldest request when the queue reaches capacity. This mirrors
    /// the Android SDK's `queuedTime`. Defaults to the current time when the request
    /// is created.
    public let enqueuedAt: Date

    /// Creates a new request to the Klaviyo API.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this request. If not provided, a UUID will be generated.
    ///   - endpoint: The endpoint this request will target.
    ///   - enqueuedAt: The time this request was enqueued. Defaults to the current time.
    public init(
        id: String = environment.uuid().uuidString,
        endpoint: KlaviyoEndpoint,
        enqueuedAt: Date = environment.date()
    ) {
        self.id = id
        self.endpoint = endpoint
        self.enqueuedAt = enqueuedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case endpoint
        case enqueuedAt
    }

    /// Custom decoding that stays backward compatible with queues persisted before
    /// `enqueuedAt` existed (e.g. requests carried across an app upgrade). A missing
    /// timestamp defaults to `Date.distantPast` so these legacy requests sort as the
    /// oldest and are evicted first under overflow. Because `min(by:)` returns the first
    /// minimal element, legacy entries tie-break by queue position (front-most first),
    /// which preserves their original age order.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        endpoint = try container.decode(KlaviyoEndpoint.self, forKey: .endpoint)
        enqueuedAt = try container.decodeIfPresent(Date.self, forKey: .enqueuedAt) ?? .distantPast
    }

    /// Equality intentionally ignores `enqueuedAt` so introducing the timestamp does not
    /// change dedup or state-comparison semantics — requests are identified by `id` + `endpoint`.
    public static func ==(lhs: KlaviyoRequest, rhs: KlaviyoRequest) -> Bool {
        lhs.id == rhs.id && lhs.endpoint == rhs.endpoint
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
        request.setValue(endpoint.revision, forHTTPHeaderField: "revision")
        return request
    }
}
