@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

struct QueuedRequestTests {
    static let failedAt = Date(timeIntervalSince1970: 1000)

    @Test
    func freshEntryIsSendableAtAttemptOne() {
        let entry = QueuedRequest(makeCreateProfileRequest())
        #expect(entry.attempts == 0)
        #expect(entry.nextAttemptAt == nil)
        #expect(entry.nextAttemptNumber == 1)
        #expect(!entry.isAwaitingRetry(at: Self.failedAt))
    }

    @Test
    func retryableFailureGatesUntilDeadline() {
        var entry = QueuedRequest(makeCreateProfileRequest())
        entry.recordRetryableFailure(retryAfter: 10, now: Self.failedAt)

        #expect(entry.attempts == 1)
        #expect(entry.nextAttemptNumber == 2)
        #expect(entry.nextAttemptAt == Self.failedAt.addingTimeInterval(10))
        #expect(entry.isAwaitingRetry(at: Self.failedAt))
        #expect(entry.isAwaitingRetry(at: Self.failedAt.addingTimeInterval(9.999)))
        #expect(!entry.isAwaitingRetry(at: Self.failedAt.addingTimeInterval(10)))
    }

    @Test
    func clockRollbackPastFailureReleasesBackoff() {
        var entry = QueuedRequest(makeCreateProfileRequest())
        entry.recordRetryableFailure(retryAfter: 300, now: Self.failedAt)

        #expect(!entry.isAwaitingRetry(at: Self.failedAt.addingTimeInterval(-0.001)))
    }

    @Test
    func negativeDelayIsClampedToNow() {
        var entry = QueuedRequest(makeCreateProfileRequest())
        entry.recordRetryableFailure(retryAfter: -5, now: Self.failedAt)

        #expect(entry.nextAttemptAt == Self.failedAt)
        #expect(!entry.isAwaitingRetry(at: Self.failedAt))
    }

    @Test
    func exhaustsAtEndpointMaxRetries() {
        var entry = QueuedRequest(makeLowRetryRequest())
        #expect(!entry.hasExhaustedRetries)
        entry.recordRetryableFailure(retryAfter: 0, now: Self.failedAt)
        #expect(entry.hasExhaustedRetries)
    }
}
#endif
