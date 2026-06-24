//
//  FlushGovernorSimulationTests.swift
//
//  Deterministic discrete-event simulation that A/Bs three flush strategies against the
//  same synthetic event streams, driving the REAL governor functions
//  (`consumeFlushToken`/`shouldFlushForQueueDepth`) over a virtual clock:
//
//    • legacy   — flush the whole queue on every interval tick (previous behavior)
//    • naive    — add the queue-depth early-flush trigger but NO token bucket
//    • governor — depth trigger + token bucket (this PR)
//
//  It measures flush count, per-event delivery latency, 429s against a rate-limited mock
//  backend, and the bucket's rate-ceiling. These are proof/benchmark tests: they print a
//  comparison table and assert only the properties we can guarantee. They intentionally do
//  not exercise the async send pipeline — the flush *schedule* is what the governor changes.
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

final class FlushGovernorSimulationTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    // MARK: - Simulation model

    /// Simulates the backend's per-window request limit. Returns `false` (HTTP 429) when more
    /// than `maxRequestsPerWindow` successful requests land within `windowSeconds`.
    private struct ServerModel {
        var maxRequestsPerWindow: Int
        var windowSeconds: TimeInterval
        var retryAfter: TimeInterval
        var successTimes: [TimeInterval] = []

        static var unlimited: ServerModel {
            ServerModel(maxRequestsPerWindow: .max, windowSeconds: 1, retryAfter: 0)
        }

        mutating func attempt(at time: TimeInterval) -> Bool {
            successTimes = successTimes.filter { $0 > time - windowSeconds }
            guard successTimes.count < maxRequestsPerWindow else {
                return false
            }
            successTimes.append(time)
            return true
        }
    }

    private struct SimMetrics {
        var flushTimes: [TimeInterval] = []
        var latencies: [TimeInterval] = []
        var http429 = 0
        var firstFlushTime: TimeInterval?

        var flushCount: Int { flushTimes.count }
        var deliveredCount: Int { latencies.count }

        func percentile(_ fraction: Double) -> TimeInterval {
            guard !latencies.isEmpty else { return 0 }
            let sorted = latencies.sorted()
            return sorted[Int((Double(sorted.count - 1) * fraction).rounded())]
        }

        func maxFlushesInWindow(_ length: TimeInterval) -> Int {
            var maxCount = 0
            for start in flushTimes {
                maxCount = max(maxCount, flushTimes.filter { $0 >= start && $0 < start + length }.count)
            }
            return maxCount
        }
    }

    private func sampleRequest() -> KlaviyoRequest {
        KlaviyoRequest(endpoint: .createEvent("foo", CreateEventPayload(data: .init(name: "sim"))))
    }

    /// Runs the discrete-event simulation.
    /// - Parameters:
    ///   - depthTrigger: flush early when the queue reaches `flushDepth`.
    ///   - tokenBucket: gate every flush through the token bucket.
    // swiftlint:disable:next function_body_length
    private func simulate(
        arrivals: [TimeInterval],
        flushInterval: TimeInterval,
        depthTrigger: Bool,
        tokenBucket: Bool,
        server: ServerModel,
        tailIntervals: Int = 80
    ) -> SimMetrics {
        var server = server
        var metrics = SimMetrics()
        var state = KlaviyoState(queue: [])
        state.flushInterval = flushInterval

        var pending: [TimeInterval] = []
        var serverRetryUntil = -TimeInterval.greatestFiniteMagnitude

        func attemptFlush(at time: TimeInterval) {
            if time < serverRetryUntil { return }
            if state.queue.isEmpty { return }
            if tokenBucket,
               !state.consumeFlushToken(currentTime: Date(timeIntervalSinceReferenceDate: time)) { return }

            metrics.flushTimes.append(time)
            if metrics.firstFlushTime == nil { metrics.firstFlushTime = time }

            if server.attempt(at: time) {
                metrics.latencies.append(contentsOf: pending.map { time - $0 })
                pending.removeAll()
                state.queue.removeAll()
            } else {
                metrics.http429 += 1
                serverRetryUntil = time + server.retryAfter
            }
        }

        let sortedArrivals = arrivals.sorted()
        let lastArrival = sortedArrivals.last ?? 0
        let maxTime = lastArrival + Double(tailIntervals) * flushInterval

        var tickTimes: [TimeInterval] = []
        var tick = flushInterval
        while tick <= maxTime {
            tickTimes.append(tick)
            tick += flushInterval
        }

        var arrivalIndex = 0
        var tickIndex = 0
        while arrivalIndex < sortedArrivals.count || tickIndex < tickTimes.count {
            let nextArrival = arrivalIndex < sortedArrivals.count
                ? sortedArrivals[arrivalIndex] : .greatestFiniteMagnitude
            let nextTick = tickIndex < tickTimes.count
                ? tickTimes[tickIndex] : .greatestFiniteMagnitude

            if nextArrival <= nextTick {
                let time = nextArrival
                while arrivalIndex < sortedArrivals.count, sortedArrivals[arrivalIndex] == time {
                    state.queue.append(sampleRequest())
                    pending.append(time)
                    if depthTrigger, state.shouldFlushForQueueDepth {
                        attemptFlush(at: time)
                    }
                    arrivalIndex += 1
                }
            } else {
                attemptFlush(at: nextTick)
                tickIndex += 1
                if state.queue.isEmpty, arrivalIndex >= sortedArrivals.count {
                    break
                }
            }
        }
        return metrics
    }

    private func report(_ scenario: String, _ columns: [(String, SimMetrics)]) {
        func fmt(_ value: TimeInterval) -> String { String(format: "%.2f", value) }
        func row(_ label: String, _ values: [String]) -> String {
            let head = label.padding(toLength: 20, withPad: " ", startingAt: 0)
            return "  " + head + values.map { $0.padding(toLength: 12, withPad: " ", startingAt: 0) }.joined()
        }
        var lines = ["", "── Flush governor simulation: \(scenario) ──"]
        lines.append(row("", columns.map(\.0)))
        lines.append(row("flushes", columns.map { String($0.1.flushCount) }))
        lines.append(row("first flush (s)", columns.map { fmt($0.1.firstFlushTime ?? -1) }))
        lines.append(row("delivered", columns.map { String($0.1.deliveredCount) }))
        lines.append(row("latency p50 (s)", columns.map { fmt($0.1.percentile(0.5)) }))
        lines.append(row("latency p95 (s)", columns.map { fmt($0.1.percentile(0.95)) }))
        lines.append(row("HTTP 429s", columns.map { String($0.1.http429) }))
        lines.append(row("max flushes/10s", columns.map { String($0.1.maxFlushesInWindow(10)) }))
        print(lines.joined(separator: "\n"))
    }

    // MARK: - Scenario 1: post-idle burst latency (governor vs legacy)

    func test_scenario1_burstAfterIdle_governorLowersLatency() {
        let arrivals = Array(repeating: 0.0, count: 50)
        let interval = StateManagementConstants.wifiFlushInterval

        let governor = simulate(arrivals: arrivals, flushInterval: interval,
                                depthTrigger: true, tokenBucket: true, server: .unlimited)
        let legacy = simulate(arrivals: arrivals, flushInterval: interval,
                              depthTrigger: false, tokenBucket: false, server: .unlimited)
        report("1 — 50-event burst after idle (wifi)", [("governor", governor), ("legacy", legacy)])

        XCTAssertEqual(governor.deliveredCount, 50)
        XCTAssertEqual(legacy.deliveredCount, 50)
        XCTAssertEqual(governor.firstFlushTime ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(legacy.firstFlushTime ?? -1, interval, accuracy: 0.001)
        XCTAssertLessThan(governor.percentile(0.95), legacy.percentile(0.95))
    }

    // MARK: - Scenario 2: steady light traffic (no regression vs legacy)

    func test_scenario2_lightTraffic_noRegressionVsLegacy() {
        let arrivals = stride(from: 0.0, through: 300.0, by: 30.0).map { $0 }
        let interval = StateManagementConstants.wifiFlushInterval

        let governor = simulate(arrivals: arrivals, flushInterval: interval,
                                depthTrigger: true, tokenBucket: true, server: .unlimited)
        let legacy = simulate(arrivals: arrivals, flushInterval: interval,
                              depthTrigger: false, tokenBucket: false, server: .unlimited)
        report("2 — steady light traffic (1 evt / 30s)", [("governor", governor), ("legacy", legacy)])

        XCTAssertEqual(governor.deliveredCount, arrivals.count)
        XCTAssertEqual(legacy.deliveredCount, arrivals.count)
        XCTAssertEqual(governor.flushCount, legacy.flushCount)
    }

    // MARK: - Scenario 3: sustained flood — the bucket bounds the depth trigger

    func test_scenario3_sustainedFlood_bucketBoundsRateAndAvoids429s() {
        let arrivals = stride(from: 0.05, through: 30.0, by: 0.05).map { $0 } // 20 evt/s for 30s
        let interval = StateManagementConstants.wifiFlushInterval
        // Illustrative backend limit: 6 requests per 10s window.
        let server = ServerModel(maxRequestsPerWindow: 6, windowSeconds: 10, retryAfter: 10)

        let legacy = simulate(arrivals: arrivals, flushInterval: interval,
                              depthTrigger: false, tokenBucket: false, server: server)
        let naive = simulate(arrivals: arrivals, flushInterval: interval,
                             depthTrigger: true, tokenBucket: false, server: server)
        let governor = simulate(arrivals: arrivals, flushInterval: interval,
                                depthTrigger: true, tokenBucket: true, server: server)
        report("3 — sustained flood (20 evt/s, limit 6/10s)",
               [("legacy", legacy), ("naive", naive), ("governor", governor)])

        // No loss under any strategy.
        XCTAssertEqual(legacy.deliveredCount, arrivals.count)
        XCTAssertEqual(naive.deliveredCount, arrivals.count)
        XCTAssertEqual(governor.deliveredCount, arrivals.count)

        // The bucket's guarantee: capacity + one refill per interval-length window.
        let ceiling = Int(StateManagementConstants.flushTokenBucketCapacity) + 1
        XCTAssertLessThanOrEqual(governor.maxFlushesInWindow(interval), ceiling)

        // The whole point of the bucket: it reins in the naive depth trigger's request storm,
        // so it incurs no more 429s than the unbounded version.
        XCTAssertLessThanOrEqual(governor.http429, naive.http429)
    }
}
