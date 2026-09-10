//
//  RequestQueueSupport.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

// MARK: - Flush timing constants

/// Flush-timing constants shared between the KlaviyoSwift reducer and the KlaviyoCore request-queue engine.
public enum FlushConstants {
    public static let wifiFlushInterval = 10.0
    public static let cellularFlushInterval = 30.0
    public static let initialAttempt = 1
}

// MARK: - RetryState

/// Describes how the state machine should handle retrying a request after a failure.
public enum RetryState: Equatable {
    /// Indicates that the request should be retried immediately (subject to
    /// the regular flush cadence).
    ///
    /// - Parameter currentCount: The attempt number for the *current* request.
    ///   The value should start at `1` for the very first send and is incremented each
    ///   time a transient failure (such as a network error) occurs.
    case retry(_ currentCount: Int)

    /// Indicates that the request should be retried after waiting for a
    /// server-specified back-off interval. This path is typically triggered by
    /// an HTTP 429 "Too Many Requests" response that includes a `Retry-After`
    /// header.
    ///
    /// - Parameters:
    ///   - requestCount: The number of attempts made for this specific request.
    ///   - totalRetryCount: The total number of attempts made for this request across all retry strategies.
    ///   - currentBackoff: The remaining time in seconds to wait before the next retry attempt.
    case retryWithBackoff(requestCount: Int, totalRetryCount: Int, currentBackoff: Int)
}

// MARK: - maxRetries

extension KlaviyoEndpoint {
    public var maxRetries: Int {
        switch self {
        case .createProfile,
             .registerPushToken,
             .unregisterPushToken,
             .createEvent,
             .aggregateEvent,
             .logTrackingLinkClicked,
             .createSubscription:
            return 50
        case .resolveDestinationURL, .fetchGeofences:
            return 1
        }
    }
}

// MARK: - InvalidField

/// Represents a field that was rejected by the Klaviyo API with an unrecoverable validation error.
public enum InvalidField: Equatable {
    case email
    case phone

    /// gets the invalid field based on the source.pointer from klaviyo API.
    /// this assumes that source.pointer will not change
    /// Client APIs to have better error codes in the future at which point we should use that instead
    /// of source.pointer
    /// - Parameter sourcePointer: pointers to the source of the error
    /// - Returns: the field that is invalid else `nil`
    public static func getInvalidField(sourcePointer: String) -> InvalidField? {
        if sourcePointer.contains("/attributes/phone_number") {
            return .phone
        }
        if sourcePointer.contains("/attributes/email") {
            return .email
        }

        return nil
    }
}

// MARK: - Error models

struct ErrorResponse: Codable {
    let errors: [ErrorDetail]
}

struct ErrorDetail: Codable {
    let id: String
    let status: Int
    let code: String
    let title: String
    let detail: String
    let source: ErrorSource
}

struct ErrorSource: Codable {
    let pointer: String
}

// MARK: - parseError helper

/// Decodes a Klaviyo API error-response body and extracts any ``InvalidField`` entries.
/// Returns `nil` if the body cannot be decoded as an error response.
public func parseError(_ data: Data, log: (String) -> Void = { _ in }) -> [InvalidField]? {
    var invalidFields: [InvalidField]?
    do {
        let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)

        invalidFields = errorResponse.errors.compactMap { error in
            InvalidField.getInvalidField(sourcePointer: error.source.pointer)
        }
    } catch {
        log("error when decoding error data")
    }

    return invalidFields
}
