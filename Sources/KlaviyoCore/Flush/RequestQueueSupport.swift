//
//  RequestQueueSupport.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

// MARK: - Flush timing constants

public enum FlushConstants {
    public static let wifiFlushInterval = 10.0
    public static let cellularFlushInterval = 30.0
}

/// Seconds the run loop should sleep before the next flush: the head's remaining backoff when it has
/// one (zero once due, so an expired retry fires at once), otherwise one flush interval.
func nextFlushDelay(head: QueuedRequest?, now: Date, flushInterval: TimeInterval) -> TimeInterval {
    guard let head, let deadline = head.nextAttemptAt else { return flushInterval }
    guard head.isAwaitingRetry(at: now) else { return 0 }
    return max(0, deadline.timeIntervalSince(now))
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

    /// A transport, rate-limit or server error occurred: retry this request after `backoff` seconds.
    /// The engine records the attempt and deadline on the request's own `QueuedRequest`.
    case retry(backoff: Int)

    /// The server rejected a field (e.g. email or phone) with a validation error.
    /// Strip the offending field(s) and remove the request from the queue.
    case clearInvalidFieldsAndDequeue([InvalidField])
}

// MARK: - classifyFailure

/// Maps a ``KlaviyoAPIError`` to a ``FlushDecision``, applying the same classification
/// logic as `handleRequestError` in `KlaviyoSwift` so the Core-side queue engine can
/// act on failure outcomes directly.
///
/// - Parameters:
///   - error: The API error returned by the network layer.
///   - attemptNumber: The 1-based ordinal of the send that just failed, for this request alone.
/// - Returns: The decision the queue engine should act on.
public func classifyFailure(error: KlaviyoAPIError, attemptNumber: Int) -> FlushDecision {
    switch error {
    case let .httpError(_, data):
        // TODO(cutover): wire environment.logger so a malformed 4xx body isn't silently classified
        // as .dequeue — `parseError` accepts an optional `log:` closure; wire `environment.logger`
        // here once the logger seam is plumbed into `RequestQueue`.
        let invalidFields = parseError(data)
        if let invalidFields, !invalidFields.isEmpty {
            return .clearInvalidFieldsAndDequeue(invalidFields)
        } else {
            return .dequeue
        }

    case .networkError:
        // Transport-level failure: the same exponential backoff as a 429/5xx (2^1, 2^2, ...), keyed
        // on this request's own failed attempt so it escalates in lockstep with that path.
        let backOff = RetryBackoffConstants.exponentialBackoff(attemptNumber: attemptNumber)
            + environment.randomInt()
        return .retry(backoff: backOff)

    case let .rateLimitError(backOff), let .serverError(_, backOff):
        // `KlaviyoAPI` already folded Retry-After, exponential backoff and jitter into `backOff`.
        return .retry(backoff: backOff)

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
