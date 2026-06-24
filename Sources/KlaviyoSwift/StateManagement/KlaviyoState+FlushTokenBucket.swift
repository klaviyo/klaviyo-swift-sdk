//
//  KlaviyoState+FlushTokenBucket.swift
//
//  Demand-adaptive flush governor: a token-bucket rate limiter plus a queue-depth
//  early-flush trigger. Together these let the SDK absorb bursts of activity after
//  idle periods while capping the long-term flush rate, instead of flushing on a
//  rigid fixed interval regardless of demand.
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation

extension KlaviyoState {
    /// Resets the token bucket to full capacity with no recorded refill timestamp,
    /// reproducing the cold-launch state. Call this whenever a new API key is set so
    /// the bucket from the previous company does not throttle the incoming company's
    /// first flush cycle.
    mutating func resetFlushTokenBucket() {
        availableFlushTokens = StateManagementConstants.flushTokenBucketCapacity
        lastFlushTokenRefill = nil
    }

    /// `true` when the queue has grown large enough to warrant an early flush attempt
    /// rather than waiting for the next flush-interval tick. Suppressed when the
    /// `flushInterval` is non-finite (i.e. offline) so we don't kick off doomed requests.
    var shouldFlushForQueueDepth: Bool {
        flushInterval.isFinite && queue.count >= StateManagementConstants.flushDepth
    }

    /// Refills the flush-token bucket based on the time elapsed since the last refill, then
    /// attempts to consume a single token.
    ///
    /// Tokens accrue at a rate of `1 / flushInterval` per second (the same network-aware
    /// cadence used by the flush timer) and are capped at `flushTokenBucketCapacity`. Because
    /// the bucket can bank up to `capacity` tokens during quiet periods, a burst of flushes
    /// immediately after an idle stretch is allowed through, while sustained activity is
    /// throttled to the long-term refill rate. When offline (`flushInterval` is non-finite)
    /// the bucket is frozen — no tokens accrue until connectivity returns.
    ///
    /// - Parameter currentTime: The current time, injected for testability.
    /// - Returns: `true` if a token was available and consumed (the caller may flush);
    ///   `false` if the bucket is empty (the caller should defer until tokens refill).
    mutating func consumeFlushToken(currentTime: Date) -> Bool {
        if let lastRefill = lastFlushTokenRefill,
           flushInterval.isFinite, flushInterval > 0 {
            let elapsed = currentTime.timeIntervalSince(lastRefill)
            if elapsed > 0 {
                let refillRate = 1.0 / flushInterval // tokens per second
                availableFlushTokens = min(
                    StateManagementConstants.flushTokenBucketCapacity,
                    availableFlushTokens + elapsed * refillRate
                )
            }
        }
        lastFlushTokenRefill = currentTime

        guard availableFlushTokens >= 1.0 else {
            return false
        }
        availableFlushTokens -= 1.0
        return true
    }
}
