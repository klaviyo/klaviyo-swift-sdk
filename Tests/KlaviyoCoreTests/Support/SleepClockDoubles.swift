//
//  SleepClockDoubles.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//
//
// Test doubles for the `SleepClock` timing seam, shared by the `RequestQueue` parity tests:
// `.immediate` returns without waiting; `RecordingSleepClock` captures requested durations so
// backoff/interval timing can be asserted deterministically without wall-clock delays.
// `GatedSleepClock` parks each sleep on a continuation so the run loop advances one controlled
// step at a time.
//

@testable import KlaviyoCore
import Foundation

extension SleepClock {
    /// Returns immediately, ignoring the requested duration.
    static var immediate: SleepClock { SleepClock { _ in } }
}

/// Captures the durations passed to `sleep`, in order, without waiting. Thread-safe so it can be
/// used from the actor under test.
final class RecordingSleepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [TimeInterval] = []

    var requested: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _requested
    }

    var clock: SleepClock {
        SleepClock { [self] seconds in
            lock.lock(); _requested.append(seconds); lock.unlock()
        }
    }
}

/// A clock that records each requested sleep duration and then suspends the run loop until the
/// test consumes one tick. This makes the loop advance one controlled step at a time so the
/// stub `flush()` cannot busy-spin thousands of ticks between assertions.
final class GatedSleepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [TimeInterval] = []
    // The loop parks on this continuation each tick; the test resumes it to release one step.
    private var _waiter: CheckedContinuation<Void, Never>?

    var requested: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _requested
    }

    var clock: SleepClock {
        SleepClock { [self] seconds in
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
                        _waiter = continuation
                        lock.unlock()
                    }
                }
            } onCancel: {
                resumeWaiter()
            }
        }
    }

    /// Releases exactly one parked sleep, letting the loop run one `flush()` and re-park.
    func releaseOneTick() { resumeWaiter() }

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
            if requested.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return requested.count >= count
    }
}
