//
//  QueuedRequest.swift
//  KlaviyoCore
//
//  Created by Claude Code on 2025-11-10.
//

import Foundation

/// A request in the queue with retry state and metadata
struct QueuedRequest: Identifiable, Equatable, Codable, Sendable {
    /// The underlying Klaviyo request
    let request: KlaviyoRequest

    /// Number of times this request has been attempted
    var retryCount: Int

    /// Time when this request was created
    let createdAt: Date

    /// Time until which this request should not be processed (for backoff)
    var backoffUntil: Date?

    /// Unique identifier (delegated to request.id)
    var id: String { request.id }

    init(
        request: KlaviyoRequest,
        retryCount: Int = 0,
        createdAt: Date = environment.date(),
        backoffUntil: Date? = nil
    ) {
        self.request = request
        self.retryCount = retryCount
        self.createdAt = createdAt
        self.backoffUntil = backoffUntil
    }

    /// Check if this request is ready to be processed (not in backoff)
    func isReadyToProcess(at date: Date = environment.date()) -> Bool {
        guard let backoff = backoffUntil else { return true }
        return date >= backoff
    }

    /// Create a new instance with incremented retry count
    func withIncrementedRetry() -> QueuedRequest {
        QueuedRequest(
            request: request,
            retryCount: retryCount + 1,
            createdAt: createdAt,
            backoffUntil: backoffUntil
        )
    }

    /// Create a new instance with backoff set
    func withBackoff(until date: Date) -> QueuedRequest {
        QueuedRequest(
            request: request,
            retryCount: retryCount,
            createdAt: createdAt,
            backoffUntil: date
        )
    }
}
