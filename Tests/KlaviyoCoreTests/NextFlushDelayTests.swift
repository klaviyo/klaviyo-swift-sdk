//
//  NextFlushDelayTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

/// Pure-function tests: explicit dates and values only, no global state, so they are safe to run
/// in parallel with other suites.
struct NextFlushDelayTests {
    static let now = Date(timeIntervalSince1970: 1_234_567_890)

    private func backingOffHead(retryAfter delay: Int) -> QueuedRequest {
        var head = QueuedRequest(makeCreateProfileRequest())
        head.recordRetryableFailure(retryAfter: delay, now: Self.now)
        return head
    }

    @Test
    func delayIsFlushIntervalWithoutBackoff() {
        #expect(nextFlushDelay(head: nil, now: Self.now, flushInterval: 10) == 10)
        let fresh = QueuedRequest(makeCreateProfileRequest())
        #expect(nextFlushDelay(head: fresh, now: Self.now, flushInterval: 30) == 30)
    }

    @Test
    func delayIsRemainingBackoffNotATickMultiple() {
        let head = backingOffHead(retryAfter: 37)

        #expect(nextFlushDelay(head: head, now: Self.now, flushInterval: 10) == 37)
        #expect(nextFlushDelay(head: head, now: Self.now.addingTimeInterval(30), flushInterval: 10) == 7)
    }

    @Test
    func dueBackoffHasZeroDelay() {
        let head = backingOffHead(retryAfter: 37)

        #expect(nextFlushDelay(head: head, now: Self.now.addingTimeInterval(37), flushInterval: 10) == 0)
        #expect(nextFlushDelay(head: head, now: Self.now.addingTimeInterval(500), flushInterval: 10) == 0)
    }
}
#endif
