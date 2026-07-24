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
    /// `flushInterval` is non-finite (i.e. offline) so we don't kick off doomed requests, and
    /// while a server-mandated `Retry-After` backoff is active — otherwise every enqueued event
    /// during a large backoff window would independently trigger `.flushQueue`, and each call
    /// erodes `retryState`'s `currentBackoff` by a full flush interval, eating into the
    /// server-mandated wait far faster than intended.
    var shouldFlushForQueueDepth: Bool {
        guard flushInterval.isFinite else { return false }
        if case .retryWithBackoff = retryState { return false }
        return queue.count >= StateManagementConstants.flushDepth
    }

    /// Consumes the prioritized-flush flag set by an opened-push or geofence event (see
    /// `pendingPrioritizedFlush`), returning whether the caller should bypass the token-bucket
    /// gate for this `.flushQueue` attempt. The flag is cleared unconditionally — regardless of
    /// the returned value — so it never leaks into a later, unrelated flush attempt.
    mutating func consumePendingPrioritizedFlush() -> Bool {
        defer { pendingPrioritizedFlush = false }
        return pendingPrioritizedFlush
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
        // Only ever advance the refill timestamp forward. A backward clock jump (manual clock
        // change, NTP correction) must not rewind `lastFlushTokenRefill` — otherwise a later call
        // using the "real" (forward) time would compute an inflated `elapsed` and grant a
        // windfall refill instead of being correctly denied.
        if let lastRefill = lastFlushTokenRefill, currentTime < lastRefill {
            // Clock moved backward: keep the existing (later) timestamp.
        } else {
            lastFlushTokenRefill = currentTime
        }

        guard availableFlushTokens >= 1.0 else {
            return false
        }
        availableFlushTokens -= 1.0
        return true
    }
}
