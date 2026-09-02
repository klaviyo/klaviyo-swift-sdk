//
//  FlushGovernor.swift
//
//  Demand-adaptive flush governor: a token bucket that paces outbound API
//  requests instead of flush cycles.
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation

/// Tunables for the flush governor.
///
/// The refill rate is expressed in **requests per second**, not flushes per second. This is the
/// central design point: a single flush drains the whole queue one HTTP request at a time (see
/// `.sendRequest` / `.deQueueCompletedResults`), so pacing flush *cycles* places no bound at all on
/// the request rate. Pacing requests does.
enum FlushGovernorConstants {
    /// Burst allowance, in requests. Tokens accrue while the app is idle up to this ceiling, so a
    /// burst of activity after a quiet stretch is sent immediately rather than waiting for the next
    /// flush tick. This is the knob that buys post-idle responsiveness.
    static let burstCapacity = 20.0

    /// Sustained ceiling on wifi, in requests/second. Well above ordinary app traffic (a handful of
    /// events per minute) and well below a pathological storm, so normal usage never touches the
    /// governor while a runaway loop is bounded.
    static let wifiRefillPerSecond = 2.0

    /// Sustained ceiling on cellular, in requests/second. Lower than wifi for radio/battery cost,
    /// mirroring the existing tiered flush intervals.
    static let cellularRefillPerSecond = 1.0
}

/// A token bucket that paces outbound requests.
///
/// One token is spent per HTTP request. Tokens accrue continuously at `refillPerSecond` up to
/// `capacity`. Because the bucket banks idle time, it absorbs bursts without raising the long-run
/// average, which is what "demand-adaptive" means here: cadence follows demand over time rather
/// than a fixed timer.
///
/// Refill is computed lazily from elapsed wall-clock time rather than driven by a timer, so the
/// bucket costs nothing while the app is quiet and needs no scheduling of its own.
struct FlushGovernor: Equatable {
    /// Available tokens. Fractional between refills; may go negative when a prioritized request
    /// overdraws the bucket (see `debitForPrioritizedRequest()`).
    private(set) var tokens: Double

    /// Timestamp of the last refill computation. `nil` until the first request is considered.
    private(set) var lastRefill: Date?

    let capacity: Double

    init(
        capacity: Double = FlushGovernorConstants.burstCapacity,
        tokens: Double? = nil,
        lastRefill: Date? = nil
    ) {
        self.capacity = capacity
        // Start full: a cold launch should never be throttled, and the first send goes immediately.
        self.tokens = tokens ?? capacity
        self.lastRefill = lastRefill
    }

    /// Requests/second for the current network tier. Returns `nil` when offline, which freezes the
    /// bucket — no accrual while we cannot send, so reconnecting does not hand out a windfall
    /// proportional to time spent offline.
    ///
    /// Derived from `flushInterval` so the governor subsumes the existing network tiering rather
    /// than competing with it.
    static func refillPerSecond(forFlushInterval flushInterval: Double) -> Double? {
        guard flushInterval.isFinite, flushInterval > 0 else { return nil }
        return flushInterval <= StateManagementConstants.wifiFlushInterval
            ? FlushGovernorConstants.wifiRefillPerSecond
            : FlushGovernorConstants.cellularRefillPerSecond
    }

    /// Accrues tokens for time elapsed since the last refill, capped at `capacity`.
    ///
    /// A backward clock jump (manual change, NTP correction) must never rewind `lastRefill`,
    /// otherwise a later reading against the stale timestamp would compute an inflated elapsed
    /// interval and grant a windfall. The timestamp therefore only ever moves forward.
    mutating func refill(currentTime: Date, flushInterval: Double) {
        guard let rate = Self.refillPerSecond(forFlushInterval: flushInterval) else {
            // Offline: freeze. Still advance the clock so the offline stretch accrues nothing once
            // connectivity returns.
            if let last = lastRefill, currentTime > last {
                lastRefill = currentTime
            } else if lastRefill == nil {
                lastRefill = currentTime
            }
            return
        }

        defer {
            if let last = lastRefill {
                if currentTime > last { lastRefill = currentTime }
            } else {
                lastRefill = currentTime
            }
        }

        guard let last = lastRefill else { return }
        let elapsed = currentTime.timeIntervalSince(last)
        guard elapsed > 0 else { return }
        tokens = min(capacity, tokens + elapsed * rate)
    }

    /// Whether a request may be sent right now, without consuming anything.
    ///
    /// Used by the enqueue path to decide whether to flush immediately, so a doomed early flush is
    /// never scheduled.
    func canSend(currentTime: Date, flushInterval: Double) -> Bool {
        var copy = self
        copy.refill(currentTime: currentTime, flushInterval: flushInterval)
        return copy.tokens >= 1.0
    }

    /// Refills, then spends one token if available.
    ///
    /// - Returns: `true` when the caller may send. `false` means the bucket is dry and the caller
    ///   should leave the request queued; the next flush tick retries it.
    mutating func consume(currentTime: Date, flushInterval: Double) -> Bool {
        refill(currentTime: currentTime, flushInterval: flushInterval)
        guard tokens >= 1.0 else { return false }
        tokens -= 1.0
        return true
    }

    /// Spends a token for a prioritized request (opened-push, geofence) that is exempt from the
    /// gate, allowing the balance to go negative.
    ///
    /// Engagement events must never be delayed, but they are still real load on the backend, so
    /// they are debited rather than waved through for free. Overdrawing simply means ordinary
    /// traffic waits slightly longer afterwards, which keeps the long-run ceiling honest — a
    /// meaningful difference from bypassing the bucket entirely.
    mutating func debitForPrioritizedRequest(currentTime: Date, flushInterval: Double) {
        refill(currentTime: currentTime, flushInterval: flushInterval)
        tokens -= 1.0
    }

    /// Seconds until at least one token is available, or `nil` if the bucket is frozen (offline) and
    /// will never refill on its own. Reported for diagnostics and to size test expectations.
    func timeUntilNextToken(flushInterval: Double) -> Double? {
        if tokens >= 1.0 { return 0 }
        guard let rate = Self.refillPerSecond(forFlushInterval: flushInterval), rate > 0 else {
            return nil
        }
        return (1.0 - tokens) / rate
    }

    /// Restores the bucket to a cold-launch state. Called when the API key changes so one company's
    /// traffic cannot throttle the next.
    mutating func reset() {
        tokens = capacity
        lastRefill = nil
    }
}
