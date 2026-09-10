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
