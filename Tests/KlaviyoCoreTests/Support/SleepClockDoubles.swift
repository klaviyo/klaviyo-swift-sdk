//
//  SleepClockDoubles.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//
//
// Test doubles for the `SleepClock` timing seam, shared by the `RequestQueue` parity tests:
// `.immediate` returns without waiting. `GatedSleepClock` parks each sleep on a continuation so the
// run loop advances one controlled step at a time.
//

@testable import KlaviyoCore
import Foundation

extension SleepClock {
    /// Returns immediately, ignoring the requested duration. `now` is fixed at a constant test
    /// instant unless `now:` is supplied, so absolute per-lane backoff deadlines are deterministic.
    static var immediate: SleepClock {
        immediate()
    }

    /// An immediate clock whose `now` reads from the given provider (fixed test instant by
    /// default).
    static func immediate(now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1000) }) -> SleepClock {
        SleepClock(sleep: { _ in }, now: now)
    }
}

/// A thread-safe mutable wall clock for the absolute per-lane backoff deadline tests: the queue
/// reads `now` from it, and the test advances time explicitly (no real sleeps).
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(start: Date = Date(timeIntervalSince1970: 1000)) {
        _now = start
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        _now = _now.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// A clock that records each requested sleep duration and then suspends the run loop until the
/// test consumes one tick. This makes the loop advance one controlled step at a time so the
/// stub `flush()` cannot busy-spin thousands of ticks between assertions.
final class GatedSleepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [TimeInterval] = []
    /// The loop parks on this continuation each tick; the test resumes it to release one step.
    private var _waiter: CheckedContinuation<Void, Never>?
    /// Sleeps that actually PARKED, in park order. Unlike `requested` (which also records a sleep
    /// that started already-cancelled), this reflects real scheduled sleeps, so a cancelled wake's
    /// truncated sleep doesn't pollute assertions about what the queue scheduled next.
    private var _requestedSleeps: [TimeInterval] = []

    var requested: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _requested
    }

    var requestedSleeps: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _requestedSleeps
    }

    /// The wall clock the queue's `now` reads. Defaults to a real `Date()`; tests can swap in a
    /// `TestClock` provider to control absolute deadlines while gating sleeps.
    var nowProvider: @Sendable () -> Date = { Date() }

    var clock: SleepClock {
        SleepClock(sleep: { [self] seconds in
            // Resume the parked continuation on cancellation too, so a `stop()` that cancels the
            // loop mid-sleep never leaks it (which would trip CheckedContinuation's misuse trap).
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    _requested.append(seconds)
                    // If cancellation already fired, resume immediately rather than parking a
                    // continuation nobody will ever release.
                    if Task.isCancelled {
                        lock.unlock()
                        continuation.resume()
                    } else {
                        _requestedSleeps.append(seconds)
                        _waiter = continuation
                        lock.unlock()
                    }
                }
            } onCancel: {
                resumeWaiter()
            }
        }, now: { [self] in nowProvider() })
    }

    /// Releases exactly one parked sleep, letting the loop run one `flush()` and re-park.
    func releaseOneTick() {
        resumeWaiter()
    }

    private func resumeWaiter() {
        lock.lock()
        let waiter = _waiter
        _waiter = nil
        lock.unlock()
        waiter?.resume()
    }

    /// Blocks (bounded) until at least `count` sleeps have been requested.
    func waitForRequested(atLeast count: Int, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if requested.count >= count {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return requested.count >= count
    }

    /// Blocks (bounded) until at least `count` sleeps have actually PARKED. Use this (not
    /// `waitForRequested`) before asserting on `requestedSleeps`, so a not-yet-parked wake sleep
    /// can't race the assertion.
    func waitForRequestedSleeps(atLeast count: Int, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if requestedSleeps.count >= count {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return requestedSleeps.count >= count
    }
}
