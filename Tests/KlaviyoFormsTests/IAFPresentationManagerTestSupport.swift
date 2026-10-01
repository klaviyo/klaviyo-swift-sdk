//
//  IAFPresentationManagerTestSupport.swift
//  klaviyo-swift-sdk
//
//  Shared setup and polling helpers for the ``IAFPresentationManager`` test suites.
//

import KlaviyoCore
import XCTest

/// Upper bound for waits on state that is expected to change.
let presentationEventTimeout: TimeInterval = 10

/// Resets the global stores the presentation manager reads.
func resetPresentationManagerStores() {
    IdentityStore.shared.reset()
    SDKConfigStore.shared.reset()
}

extension XCTestCase {
    /// Polls `condition` until it holds or `timeout` elapses; returns its final value.
    @MainActor
    func waitUntil(
        timeout: TimeInterval = presentationEventTimeout,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }

    /// Fails the test unless `condition` holds within `timeout`.
    @MainActor
    func assertEventually(
        timeout: TimeInterval = presentationEventTimeout,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async -> Bool
    ) async {
        let held = await waitUntil(timeout: timeout, condition)
        XCTAssertTrue(held, "condition not met within \(timeout)s", file: file, line: line)
    }
}
