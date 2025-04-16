//
//  WithTimeout.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/10/25.
//

import Foundation

package enum TimeoutError: Error {
    case timeout
}

/// Executes an asynchronous operation with a specified timeout duration.
///
/// This function runs the provided asynchronous operation and ensures it completes within the specified timeout period.
/// If the operation takes longer than the timeout duration, a `TimeoutError.timeout` is thrown.
///
/// - Parameters:
///   - timeout: The maximum duration, in seconds, to wait for the operation to complete.
///   - operation: The asynchronous operation to execute.
///
/// - Returns: The result of the operation if it completes within the timeout period.
///
/// - Throws:
///   - `TimeoutError.timeout` if the operation exceeds the specified timeout duration.
///   - Any error thrown by the operation itself.
///
/// - Note: The operation is automatically cancelled if it exceeds the timeout duration.
///
/// Example:
/// ```swift
/// let result = try await withTimeout(seconds: 5.0) {
///     try await someLongRunningOperation()
/// }
/// ```
package func withTimeout<T: Sendable>(
    seconds timeout: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }

        // Add the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TimeoutError.timeout
        }

        // Return first completed task result or throw
        let result = try await group.next()!

        // Cancel any remaining tasks
        group.cancelAll()
        return result
    }
}
