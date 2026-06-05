//
//  RetryState.swift
//
//  KlaviyoCore
//

import Foundation

/// Describes how the networking layer should handle retrying a request after a failure.
public enum RetryState: Equatable {
    /// Retry at the regular flush cadence.
    /// - Parameter currentCount: The attempt number (starts at 1).
    case retry(_ currentCount: Int)

    /// Retry after a server-specified back-off interval (e.g. HTTP 429 Retry-After).
    case retryWithBackoff(requestCount: Int, totalRetryCount: Int, currentBackoff: Int)
}

public enum NetworkingConstants {
    /// Maximum back-off interval in seconds before the next retry attempt.
    public static let maxBackoff = 60 * 3 // 3 minutes
}
