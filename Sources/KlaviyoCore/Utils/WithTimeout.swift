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

package func withTimeout<T>(
    seconds timeout: TimeInterval,
    operation: @escaping () async throws -> T
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
