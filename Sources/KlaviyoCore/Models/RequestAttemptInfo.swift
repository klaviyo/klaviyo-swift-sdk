//
//  RequestAttemptInfo.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 7/23/25.
//

import OSLog

/// Represents the retry metadata for a single network request attempt.
public struct RequestAttemptInfo: Equatable {
    /// The ordinal number of the current attempt (starts at `1`).
    public let attemptNumber: Int

    /// The maximum number of attempts allowed for the request.
    public let maxAttempts: Int

    /// Error cases thrown by ``RequestAttemptInfo``'s initializer.
    public enum InitializationError: Error, Equatable {
        /// The provided values are outside of the valid range.
        case invalidRange(attemptNumber: Int, maxAttempts: Int)
    }

    /// Creates a new instance or throws ``InitializationError`` if the supplied values are invalid.
    /// - Parameters:
    ///   - attemptNumber: The current attempt count. Must be **≥ 1**.
    ///   - maxAttempts: The maximum attempts permitted. Must be **≥ attemptNumber**.
    public init(attemptNumber: Int, maxAttempts: Int) throws {
        guard attemptNumber >= 1, maxAttempts >= attemptNumber else {
            if #available(iOS 14.0, *) {
                let errorMessage = (attemptNumber < 1) ?
                    "attemptNumber is \(attemptNumber) but must be >= 1"
                    :
                    "maxAttempts is \(maxAttempts) but must be >= attemptNumber (\(attemptNumber))"
                Logger.networking.warning("Invalid attempt number values; \(errorMessage)")
            }
            throw InitializationError.invalidRange(attemptNumber: attemptNumber, maxAttempts: maxAttempts)
        }
        self.attemptNumber = attemptNumber
        self.maxAttempts = maxAttempts
    }
}
