//
//  SleepClock.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

// `now` reads the wall clock; identifier_name's 4-char floor rejects it.
// swiftlint:disable identifier_name
/// Injectable timing seam for interval/backoff sleeps and the current time. Production sleeps for
/// real and reads the wall clock; tests inject immediate/recording variants plus a scripted `now`
/// so time-dependent behavior is asserted without wall-clock waits.
public struct SleepClock: Sendable {
    public var sleep: @Sendable (_ seconds: TimeInterval) async throws -> Void
    /// Current wall-clock time. Backs the per-lane absolute backoff deadlines (`nextEligibleAt`),
    /// which must survive flush-cadence changes and never drift with the tick count.
    public var now: @Sendable () -> Date

    public init(
        sleep: @escaping @Sendable (_ seconds: TimeInterval) async throws -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sleep = sleep
        self.now = now
    }

    /// Sleeps for real via structured concurrency. Negative/zero clamp to no wait; non-finite
    /// (e.g. `.infinity`, used as the offline flush interval) or overflowing values clamp to the
    /// longest representable sleep instead of trapping the `Double`→`UInt64` conversion.
    public static let production = SleepClock { seconds in
        let nanos = max(0, seconds) * 1_000_000_000
        let clamped: UInt64 = (nanos.isFinite && nanos < Double(UInt64.max)) ? UInt64(nanos) : .max
        try await Task.sleep(nanoseconds: clamped)
    }
}

// swiftlint:enable identifier_name
