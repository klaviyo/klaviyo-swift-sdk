//
//  LifecycleEventTestSupport.swift
//  klaviyo-swift-sdk
//
//  Shared helpers for asserting on `IAFWebViewModel.formLifecycleStream` without
//  the listener-startup race + wall-clock `fulfillment` that made these tests flaky.
//

@testable import KlaviyoForms
import Foundation
import XCTest

extension XCTestCase {
    /// Asserts that `stream` emits a lifecycle event matching `predicate`.
    ///
    /// `IAFWebViewModel.handleScriptMessage(_:)` yields synchronously into the
    /// unbounded-buffered `formLifecycleStream`, so once the triggering message has
    /// been handled the event is already buffered. Consuming the stream inline —
    /// rather than spawning a listener `Task` and then waiting on a wall-clock
    /// `fulfillment(of:timeout:)` — removes the "did the listener subscribe before
    /// the event was yielded?" race and the executor-timing sensitivity that made
    /// these tests flaky (and, under load, hang) in CI.
    ///
    /// Bounded by `timeout` so a genuinely missing event fails fast instead of
    /// hanging the whole test run.
    ///
    /// - Parameter description: Human-readable name of the expected event, used in
    ///   the failure message (e.g. `"present"`).
    func assertLifecycleEvent(
        _ description: String,
        from stream: AsyncStream<IAFLifecycleEvent>,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        matching predicate: @escaping @Sendable (IAFLifecycleEvent) -> Bool
    ) async {
        let observed = await firstResult(within: timeout) {
            for await event in stream where predicate(event) {
                return true
            }
            return false
        }

        XCTAssertEqual(
            observed,
            true,
            "Expected lifecycle event '\(description)' within \(timeout)s",
            file: file,
            line: line
        )
    }
}

/// Runs `operation`, returning `nil` if it does not finish within `seconds`.
///
/// The losing child task is cancelled, which lets a suspended `AsyncStream`
/// iterator unwind rather than leak.
private func firstResult<T: Sendable>(
    within seconds: TimeInterval,
    _ operation: @Sendable @escaping () async -> T
) async -> T? {
    await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = try? await group.next()
        group.cancelAll()
        return result ?? nil
    }
}
