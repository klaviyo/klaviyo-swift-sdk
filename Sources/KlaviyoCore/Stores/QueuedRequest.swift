//
//  QueuedRequest.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Runtime queue entry: a persisted `KlaviyoRequest` plus its own retry bookkeeping.
///
/// Only `request` is persisted; `attempts`/`nextAttemptAt` live in memory and reset on relaunch,
/// matching Android. Position in `QueueStore` / the flush lease stays the source of truth for
/// queued vs in-flight, so there is deliberately no status enum.
public struct QueuedRequest: Equatable, Identifiable {
    public let request: KlaviyoRequest

    /// Failed attempts so far; `0` for a request that has never failed.
    public private(set) var attempts = 0

    /// Earliest wall-clock time this request may be resent, or `nil` when it isn't backing off.
    public private(set) var nextAttemptAt: Date?

    /// Wall-clock time of the failure that set `nextAttemptAt`; used to detect a clock rollback.
    private var lastFailedAt: Date?

    public init(_ request: KlaviyoRequest) {
        self.request = request
    }

    public var id: String { request.id }

    /// Ordinal of the next send (1-based), reported in `X-Klaviyo-Attempt-Count`.
    public var nextAttemptNumber: Int { attempts + 1 }

    /// Whether the request has used up its endpoint's attempt budget.
    public var hasExhaustedRetries: Bool { attempts >= request.endpoint.maxRetries }

    /// Whether the request is still inside its own backoff window at `now`. A clock set back past
    /// the failure time releases the backoff rather than stranding it far in the future.
    public func isAwaitingRetry(at now: Date) -> Bool {
        guard let nextAttemptAt, let lastFailedAt, now >= lastFailedAt else { return false }
        return now < nextAttemptAt
    }

    /// Records a retryable failure: counts the attempt and schedules the next one `delay` seconds out.
    mutating func recordRetryableFailure(retryAfter delay: Int, now: Date) {
        attempts += 1
        lastFailedAt = now
        nextAttemptAt = now.addingTimeInterval(TimeInterval(max(delay, 0)))
    }

    /// Drops any pending backoff so the request is due now. `attempts` is kept, so a later failure
    /// still escalates from the same count.
    mutating func clearBackoff() {
        nextAttemptAt = nil
        lastFailedAt = nil
    }
}
