//
//  FlushGovernorTests.swift
//
//  Unit tests for the token bucket, plus a discrete-event simulation comparing the
//  governor against today's timer-only behavior.
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

// MARK: - Token bucket unit tests

final class FlushGovernorTests: XCTestCase {
    private let wifi = StateManagementConstants.wifiFlushInterval
    private let cell = StateManagementConstants.cellularFlushInterval
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func test_startsFullSoColdLaunchIsNotThrottled() {
        var governor = FlushGovernor()
        XCTAssertEqual(governor.tokens, FlushGovernorConstants.burstCapacity)
        XCTAssertTrue(governor.consume(currentTime: t0, flushInterval: wifi))
    }

    func test_consumeSpendsExactlyOneTokenPerRequest() {
        var governor = FlushGovernor(capacity: 5, tokens: 5, lastRefill: t0)
        XCTAssertTrue(governor.consume(currentTime: t0, flushInterval: wifi))
        XCTAssertEqual(governor.tokens, 4, accuracy: 0.0001)
    }

    func test_deniesOnceDrainedThenAllowsAfterRefill() {
        var governor = FlushGovernor(capacity: 2, tokens: 0, lastRefill: t0)
        XCTAssertFalse(governor.consume(currentTime: t0, flushInterval: wifi))

        // Derive the wait from the configured rate so retuning the constants cannot silently
        // invalidate this test.
        let oneTokenWait = 1.0 / FlushGovernorConstants.wifiRefillPerSecond
        let later = t0.addingTimeInterval(oneTokenWait)
        XCTAssertTrue(governor.consume(currentTime: later, flushInterval: wifi))
    }

    func test_refillIsCappedAtCapacity() {
        var governor = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        governor.refill(currentTime: t0.addingTimeInterval(3600), flushInterval: wifi)
        XCTAssertEqual(governor.tokens, 20, accuracy: 0.0001)
    }

    func test_cellularRefillsSlowerThanWifi() {
        var onWifi = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        var onCell = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        let after10s = t0.addingTimeInterval(10)

        onWifi.refill(currentTime: after10s, flushInterval: wifi)
        onCell.refill(currentTime: after10s, flushInterval: cell)

        let expectedWifi = min(20.0, FlushGovernorConstants.wifiRefillPerSecond * 10)
        let expectedCell = min(20.0, FlushGovernorConstants.cellularRefillPerSecond * 10)
        XCTAssertEqual(onWifi.tokens, expectedWifi, accuracy: 0.0001)
        XCTAssertEqual(onCell.tokens, expectedCell, accuracy: 0.0001)
        // The tier relationship is the invariant worth pinning: cellular must never accrue
        // faster than wifi.
        XCTAssertLessThanOrEqual(
            FlushGovernorConstants.cellularRefillPerSecond,
            FlushGovernorConstants.wifiRefillPerSecond
        )
    }

    func test_bucketIsFrozenWhileOfflineSoReconnectGrantsNoWindfall() {
        var governor = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        // Ten minutes offline.
        governor.refill(currentTime: t0.addingTimeInterval(600), flushInterval: .infinity)
        XCTAssertEqual(governor.tokens, 0, accuracy: 0.0001)
        XCTAssertNil(FlushGovernor.refillPerSecond(forFlushInterval: .infinity))
    }

    /// The offline freeze has to be driven by the connectivity change, because nothing on the send
    /// path reaches it while offline: `canSend` refills a copy and `.sendRequest` is unreachable.
    /// This exercises `freezeForOffline` and then a real post-reconnect refill, which is what the
    /// production sequence actually does.
    func test_freezeForOffline_thenReconnect_accruesOnlyPostReconnectTime() {
        var governor = FlushGovernor(capacity: 50, tokens: 0, lastRefill: t0)

        // Connectivity drops at t0; the bucket is frozen at that instant.
        governor.freezeForOffline(currentTime: t0)

        // Ten minutes pass offline, then one second of connectivity.
        let reconnect = t0.addingTimeInterval(600)
        governor.freezeForOffline(currentTime: reconnect) // second drop/idle tick while offline
        governor.refill(currentTime: reconnect.addingTimeInterval(1), flushInterval: wifi)

        // Only the one connected second accrues, not the 600 offline seconds (which at 10/sec
        // would have filled the bucket to capacity).
        XCTAssertEqual(
            governor.tokens,
            FlushGovernorConstants.wifiRefillPerSecond,
            accuracy: 0.0001
        )
        XCTAssertLessThan(governor.tokens, governor.capacity)
    }

    func test_freezeForOffline_neverMovesTimestampBackward() {
        var governor = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        governor.freezeForOffline(currentTime: t0.addingTimeInterval(-300))
        XCTAssertEqual(governor.lastRefill, t0)
    }

    func test_backwardClockJumpDoesNotGrantWindfall() {
        var governor = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        // Clock steps backwards; must not rewind lastRefill.
        governor.refill(currentTime: t0.addingTimeInterval(-300), flushInterval: wifi)
        XCTAssertEqual(governor.tokens, 0, accuracy: 0.0001)

        // A real (forward) reading one second on should yield one second of accrual, not 301s.
        governor.refill(currentTime: t0.addingTimeInterval(1), flushInterval: wifi)
        XCTAssertEqual(
            governor.tokens,
            FlushGovernorConstants.wifiRefillPerSecond,
            accuracy: 0.0001
        )
    }

    func test_prioritizedRequestIsDebitedAndMayOverdraw() {
        var governor = FlushGovernor(capacity: 5, tokens: 0, lastRefill: t0)
        governor.debitForPrioritizedRequest(currentTime: t0, flushInterval: wifi)
        // Went negative: the engagement event was never delayed, but it still counts, so ordinary
        // traffic waits slightly longer rather than the ceiling being silently exceeded.
        XCTAssertEqual(governor.tokens, -1, accuracy: 0.0001)
    }

    /// The dry-requeue path must not bury a prioritized request behind returning regulars.
    func test_partitionedKeepsPrioritizedOrderingStable() {
        let items = ["a", "p1", "b", "p2", "c"]
        let (prioritized, regular) = items.partitioned(by: { $0.hasPrefix("p") })
        XCTAssertEqual(prioritized, ["p1", "p2"])
        XCTAssertEqual(regular, ["a", "b", "c"])
    }

    func test_resetRestoresColdLaunchState() {
        var governor = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        governor.reset()
        XCTAssertEqual(governor.tokens, 20, accuracy: 0.0001)
        XCTAssertNil(governor.lastRefill)
    }

    func test_timeUntilNextTokenTracksTier() {
        let drained = FlushGovernor(capacity: 20, tokens: 0, lastRefill: t0)
        XCTAssertEqual(
            drained.timeUntilNextToken(flushInterval: wifi) ?? -1,
            1.0 / FlushGovernorConstants.wifiRefillPerSecond,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            drained.timeUntilNextToken(flushInterval: cell) ?? -1,
            1.0 / FlushGovernorConstants.cellularRefillPerSecond,
            accuracy: 0.0001
        )
        XCTAssertNil(drained.timeUntilNextToken(flushInterval: .infinity))
    }
}

// MARK: - Simulation

/// Compares the governor against today's timer-only behavior on synthetic traffic.
///
/// The critical modeling choice, and the one the previous PoC's simulation got wrong: a flush does
/// **not** cost one server request. It drains the queue one HTTP request at a time, so the server
/// model is charged per request. Without that, throttling flush cycles looks like it bounds load
/// when it does not.
final class FlushGovernorSimulationTests: XCTestCase {
    private struct Metrics {
        var sendTimes: [TimeInterval] = []
        var latencies: [TimeInterval] = []
        var rateLimited = 0
        var firstSend: TimeInterval?

        var delivered: Int { latencies.count }

        func p95() -> TimeInterval {
            guard !latencies.isEmpty else { return 0 }
            let sorted = latencies.sorted()
            return sorted[Int((Double(sorted.count - 1) * 0.95).rounded())]
        }

        /// Peak requests observed in any window of `length` seconds. This is the number that tells
        /// us whether a long-run ceiling actually exists.
        func peakRequests(inWindow length: TimeInterval) -> Int {
            var peak = 0
            for start in sendTimes {
                peak = max(peak, sendTimes.filter { $0 >= start && $0 < start + length }.count)
            }
            return peak
        }
    }

    /// Backend that rejects anything above `limit` requests per `window` seconds.
    private struct Server {
        let limit: Int
        let window: TimeInterval
        var accepted: [TimeInterval] = []

        mutating func accept(at time: TimeInterval) -> Bool {
            accepted = accepted.filter { $0 > time - window }
            guard accepted.count < limit else { return false }
            accepted.append(time)
            return true
        }
    }

    /// Runs one scenario.
    ///
    /// - Parameter useGovernor: when false, reproduces today's behavior (flush only on the interval
    ///   tick, then drain the entire queue with no pacing).
    private func simulate(
        arrivals: [TimeInterval],
        flushInterval: TimeInterval,
        useGovernor: Bool,
        serverLimit: Int? = nil,
        horizon: TimeInterval = 600
    ) -> Metrics {
        var metrics = Metrics()
        var governor = FlushGovernor(lastRefill: Date(timeIntervalSinceReferenceDate: 0))
        var server = serverLimit.map { Server(limit: $0, window: 10) }
        var queue: [TimeInterval] = [] // enqueue timestamps
        var blockedUntil: TimeInterval = -1

        /// Attempts to drain the queue at `time`, one request at a time.
        func drain(at time: TimeInterval) {
            guard time >= blockedUntil else { return }
            while !queue.isEmpty {
                if useGovernor {
                    let now = Date(timeIntervalSinceReferenceDate: time)
                    guard governor.consume(currentTime: now, flushInterval: flushInterval) else {
                        return // dry: leave the rest queued for a later tick
                    }
                }
                if var srv = server {
                    if srv.accept(at: time) {
                        server = srv
                    } else {
                        metrics.rateLimited += 1
                        blockedUntil = time + 10 // Retry-After
                        server = srv
                        return
                    }
                }
                let enqueuedAt = queue.removeFirst()
                metrics.sendTimes.append(time)
                metrics.latencies.append(time - enqueuedAt)
                if metrics.firstSend == nil { metrics.firstSend = time }
            }
        }

        // Merge arrivals and timer ticks into one ordered event stream.
        var ticks: [TimeInterval] = []
        var tick = flushInterval
        while tick <= horizon {
            ticks.append(tick)
            tick += flushInterval
        }

        var ai = 0, ti = 0
        let sortedArrivals = arrivals.sorted()
        while ai < sortedArrivals.count || ti < ticks.count {
            let nextArrival = ai < sortedArrivals.count ? sortedArrivals[ai] : .greatestFiniteMagnitude
            let nextTick = ti < ticks.count ? ticks[ti] : .greatestFiniteMagnitude

            if nextArrival <= nextTick {
                let time = nextArrival
                while ai < sortedArrivals.count, sortedArrivals[ai] == time {
                    queue.append(time)
                    ai += 1
                }
                // Governor: try to send right away (banked tokens make this instant after idle).
                // Legacy: enqueue only; nothing leaves until the next tick.
                if useGovernor {
                    drain(at: time)
                }
            } else {
                drain(at: nextTick)
                ti += 1
            }
        }
        return metrics
    }

    private func report(_ title: String, _ columns: [(String, Metrics)]) {
        func row(_ label: String, _ values: [String]) -> String {
            "  " + label.padding(toLength: 22, withPad: " ", startingAt: 0)
                + values.map { $0.padding(toLength: 14, withPad: " ", startingAt: 0) }.joined()
        }
        var lines = ["", "== \(title) =="]
        lines.append(row("", columns.map(\.0)))
        lines.append(row("delivered", columns.map { String($0.1.delivered) }))
        lines.append(row("first send (s)", columns.map { String(format: "%.2f", $0.1.firstSend ?? -1) }))
        lines.append(row("latency p95 (s)", columns.map { String(format: "%.2f", $0.1.p95()) }))
        lines.append(row("peak req / 10s", columns.map { String($0.1.peakRequests(inWindow: 10)) }))
        lines.append(row("rate limited", columns.map { String($0.1.rateLimited) }))
        print(lines.joined(separator: "\n"))
    }

    // MARK: Scenario 1 — the burst-after-idle win

    func test_burstAfterIdle_governorSendsImmediately() {
        // Deliberately mid-interval (ticks land on multiples of 10). An arrival exactly on a tick
        // would flatter the legacy path by coincidence.
        let arrivals = Array(repeating: 125.0, count: 10) // 10 events after ~2 min idle
        let governor = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: true)
        let legacy = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: false)
        report("1 - 10-event burst mid-interval after idle (wifi)",
               [("governor", governor), ("legacy", legacy)])

        XCTAssertEqual(governor.delivered, 10)
        XCTAssertEqual(legacy.delivered, 10)

        // The governor banked tokens while idle, so the whole burst leaves on arrival.
        XCTAssertEqual(governor.firstSend ?? -1, 125.0, accuracy: 0.001)
        XCTAssertLessThan(governor.p95(), 0.001)

        // Legacy waits for the next tick (t=130), so every event eats ~5s of avoidable delay.
        XCTAssertEqual(legacy.firstSend ?? -1, 130.0, accuracy: 0.001)
        XCTAssertGreaterThan(legacy.p95(), governor.p95())
    }

    // MARK: Scenario 2 — no regression on ordinary traffic

    func test_steadyLightTraffic_noRegression() {
        let arrivals = stride(from: 0.0, through: 300.0, by: 30.0).map { $0 }
        let governor = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: true)
        let legacy = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: false)
        report("2 - steady light traffic (1 evt / 30s)",
               [("governor", governor), ("legacy", legacy)])

        XCTAssertEqual(governor.delivered, arrivals.count)
        XCTAssertEqual(legacy.delivered, arrivals.count)
        // Everything still ships, and the governor is never slower.
        XCTAssertLessThanOrEqual(governor.p95(), legacy.p95())
    }

    // MARK: Scenario 3 — the ceiling that PR #622 does not deliver

    func test_sustainedStorm_governorBoundsRequestRate() {
        // A runaway loop: 20 events/sec for 30s.
        let arrivals = stride(from: 0.05, through: 30.0, by: 0.05).map { $0 }
        let governor = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: true)
        let legacy = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: false)
        report("3 - sustained storm (20 evt/s for 30s)",
               [("governor", governor), ("legacy", legacy)])

        // The whole point: wifi refills at 2 req/s, so a 10s window admits at most
        // burstCapacity + 2*10 requests. Legacy has no bound at all.
        let ceiling = Int(FlushGovernorConstants.burstCapacity
            + FlushGovernorConstants.wifiRefillPerSecond * 10) + 1
        XCTAssertLessThanOrEqual(governor.peakRequests(inWindow: 10), ceiling)
        XCTAssertGreaterThan(legacy.peakRequests(inWindow: 10), governor.peakRequests(inWindow: 10))

        // No data loss either way: throttling defers requests, it never drops them.
        XCTAssertEqual(governor.delivered, arrivals.count)
        XCTAssertEqual(legacy.delivered, arrivals.count)

        // The cost, asserted rather than left implicit: holding a storm to a ceiling necessarily
        // means the backlog drains more slowly, so tail latency is much worse than legacy. That is
        // the real tradeoff of any rate ceiling, and whether it is acceptable is a product call,
        // not something this PoC can decide. Legacy "wins" here only by having no ceiling at all.
        XCTAssertGreaterThan(governor.p95(), legacy.p95())
    }

    // MARK: Scenario 4 — fewer 429s against a real rate limit

    func test_sustainedStorm_againstRealPushTokenLimit_neitherIsRateLimited() {
        let arrivals = stride(from: 0.05, through: 30.0, by: 0.05).map { $0 }
        // The real binding constraint: POST /client/push-tokens allows 150 req/sec burst and
        // 1,400/min steady, applied per IP/device. Expressed in the 10s window the model uses,
        // the steady budget is ~233 requests.
        let pushTokenBudgetPer10s = 233
        let governor = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: true,
                                serverLimit: pushTokenBudgetPer10s)
        let legacy = simulate(arrivals: arrivals, flushInterval: 10, useGovernor: false,
                              serverLimit: pushTokenBudgetPer10s)
        report("4 - storm vs real per-device budget (233 req/10s)",
               [("governor", governor), ("legacy", legacy)])

        // The honest result once real limits are used: a single device does not breach the
        // per-device push-token budget even without a governor, because the queue is capped at 200
        // and requests drain serially. So there are no 429s to prevent here.
        //
        // This is worth stating plainly: the "fewer 429s" argument for a client-side ceiling does
        // not survive contact with the documented limits. The governor's defensible benefit is
        // post-idle burst latency (scenario 1) plus a predictable share of the device budget
        // (scenario 3), not 429 avoidance.
        XCTAssertEqual(legacy.rateLimited, 0)
        XCTAssertEqual(governor.rateLimited, 0)
        XCTAssertEqual(governor.delivered, arrivals.count)
        XCTAssertEqual(legacy.delivered, arrivals.count)
    }
}
