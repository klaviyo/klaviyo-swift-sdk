//
//  RequestAttemptInfo.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 7/23/25.
//

/// Represents the retry metadata for a single network request attempt.
public struct RequestAttemptInfo: Equatable {
    /// The ordinal number of the current attempt (starts at `1`).
    public let attemptNumber: Int

    /// The maximum number of attempts allowed for the request.
    public let maxAttempts: Int

    /// - Parameters:
    ///   - attemptNumber: The current attempt count (must be `>= 1`).
    ///   - maxAttempts: The maximum attempts permitted (must be `>= attemptNumber`).
    public init(attemptNumber: Int, maxAttempts: Int) {
        self.attemptNumber = attemptNumber
        self.maxAttempts = maxAttempts
    }
}
