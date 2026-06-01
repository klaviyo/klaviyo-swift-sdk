//
//  OnceResolver.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Foundation

/// Serializes the first of two concurrent producers onto a
/// `CheckedContinuation` so that the loser's resume becomes a no-op. Used by
/// ``AuthTokenManager`` to race the in-flight fetch against a timeout without
/// leaning on `withThrowingTaskGroup` (which would block on the loser even
/// after the winner has resolved).
actor OnceResolver<T> {
    private var resumed = false
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// - Returns: `true` if this call won the race and resumed the
    ///   continuation; `false` if the continuation was already resumed by an
    ///   earlier call.
    @discardableResult
    func resolve(_ result: Result<T, Error>) -> Bool {
        guard !resumed else { return false }
        resumed = true
        switch result {
        case let .success(value): continuation.resume(returning: value)
        case let .failure(error): continuation.resume(throwing: error)
        }
        return true
    }
}
