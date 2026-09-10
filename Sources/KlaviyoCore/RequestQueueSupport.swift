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

// MARK: - FlushDecision

/// Describes the action the request-queue engine should take after a flush attempt fails.
public enum FlushDecision: Equatable {
    /// The request is non-retryable (or succeeded): remove it from the queue and move on.
    case dequeue

    /// A transient network error occurred; resend on the regular flush cadence.
    case retry(RetryState)

    /// A rate-limit or server error occurred; wait `seconds` before resending.
    case retryWithBackoff(RetryState, seconds: Int)

    /// The server rejected a field (e.g. email or phone) with a validation error.
    /// Strip the offending field(s) and remove the request from the queue.
    case clearInvalidFieldsAndDequeue([InvalidField])
}

// MARK: - classifyFailure

/// Maps a ``KlaviyoAPIError`` to a ``FlushDecision``, mirroring the logic of
/// `handleRequestError` in `KlaviyoSwift` but without wrapping the result in a
/// `KlaviyoAction` so that the Core-side queue engine can use it directly.
///
/// DRIFT PIN: This function's classification logic must stay behaviorally identical to
/// `handleRequestError` in `APIRequestErrorHandling.swift` (KlaviyoSwift) until the
/// cutover deletes the reducer path. Any change to error handling here MUST be mirrored
/// in `handleRequestError` (minus the action-wrapping), and vice versa.
///
/// - Parameters:
///   - error: The API error returned by the network layer.
///   - retryState: The current retry state for the failing request.
/// - Returns: The decision the queue engine should act on.
public func classifyFailure(error: KlaviyoAPIError, retryState: RetryState) -> FlushDecision {
    switch error {
    case let .httpError(_, data):
        // TODO(cutover): wire environment.logger so a malformed 4xx body isn't silently classified
        // as .dequeue — the reducer path passes a real logger; the Core path currently defaults to no-op.
        let invalidFields = parseError(data)
        if let invalidFields, !invalidFields.isEmpty {
            return .clearInvalidFieldsAndDequeue(invalidFields)
        } else {
            return .dequeue
        }

    case .networkError:
        switch retryState {
        case let .retry(count):
            return .retry(.retry(count + 1))
        case let .retryWithBackoff(requestCount, _, _):
            return .retry(.retry(requestCount + 1))
        }

    case let .rateLimitError(backOff), let .serverError(_, backOff):
        var requestRetryCount = 0
        var totalRetryCount = 0
        switch retryState {
        case let .retry(count):
            requestRetryCount = count + 1
            totalRetryCount = requestRetryCount
        case let .retryWithBackoff(requestCount, totalCount, _):
            requestRetryCount = requestCount + 1
            totalRetryCount = totalCount + 1
        }
        return .retryWithBackoff(
            .retryWithBackoff(
                requestCount: requestRetryCount,
                totalRetryCount: totalRetryCount,
                currentBackoff: backOff
            ),
            seconds: backOff
        )

    case .internalError,
         .internalRequestError,
         .unknownError,
         .dataEncodingError,
         .invalidData,
         .missingOrInvalidResponse:
        return .dequeue
    }
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
