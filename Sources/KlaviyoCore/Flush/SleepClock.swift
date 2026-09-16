//
//  SleepClock.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

/// Injectable timing seam for interval/backoff sleeps. Production sleeps for real; tests inject an
/// immediate or recording variant so time-dependent behavior is asserted without wall-clock waits.
public struct SleepClock: Sendable {
    public var sleep: @Sendable (_ seconds: TimeInterval) async throws -> Void

    public init(sleep: @escaping @Sendable (_ seconds: TimeInterval) async throws -> Void) {
        self.sleep = sleep
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
