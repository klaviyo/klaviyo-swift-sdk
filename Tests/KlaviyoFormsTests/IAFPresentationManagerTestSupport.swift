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

/// Builds a JWT tagged with `subject` that is valid at `date` (`iat` a minute before,
/// `exp` an hour after). The signature is a placeholder.
func makeTestJWT(subject: String, validAt date: Date) throws -> String {
    let seconds = date.timeIntervalSince1970
    let payload: [String: Any] = ["iat": seconds - 60, "exp": seconds + 3600, "sub": subject]
    let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
    return try [header, payload]
        .map { try base64URLEncoded(JSONSerialization.data(withJSONObject: $0)) }
        .joined(separator: ".") + ".signature"
}

private func base64URLEncoded(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A one-shot gate: ``wait()`` suspends until ``open()`` has been called.
actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
