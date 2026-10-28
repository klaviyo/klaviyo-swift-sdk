//
//  RequestQueueSchedulingTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

@Suite(.serialized)
final class RequestQueueSchedulingTests {
    private let wallClock = TestClock(Date(timeIntervalSince1970: 1_234_567_890))
    private let gated = GatedSleepClock()

    init() {
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        environment = FileIODouble().makeEnvironment()
        let wallClock = wallClock
        environment.date = { wallClock.now() }
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "test-api-key"))
        QueueStore.register(makeQueueStore())
    }

    deinit {
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        environment = KlaviyoEnvironment.test()
    }

    private func makeQueue(_ spy: SendSpy) -> RequestQueue {
        RequestQueue(clock: gated.clock, send: spy.send)
    }

    private func enqueueOne() {
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "r"), persist: .synchronous)
    }

    /// Seconds from now until the head's recorded retry deadline.
    private var headDelay: TimeInterval? {
        QueueStore.shared.head?.nextAttemptAt?.timeIntervalSince(wallClock.now())
    }

    // MARK: - nextFlushDelay

    @Test
    func delayIsFlushIntervalWithoutBackoff() {
        let now = wallClock.now()
        #expect(nextFlushDelay(head: nil, now: now, flushInterval: 10) == 10)
        #expect(nextFlushDelay(head: QueuedRequest(makeCreateProfileRequest()), now: now, flushInterval: 30) == 30)
    }

    @Test
    func delayIsRemainingBackoffNotATickMultiple() {
        var head = QueuedRequest(makeCreateProfileRequest())
        let now = wallClock.now()
        head.recordRetryableFailure(retryAfter: 37, now: now)

        #expect(nextFlushDelay(head: head, now: now, flushInterval: 10) == 37)
        #expect(nextFlushDelay(head: head, now: now.addingTimeInterval(30), flushInterval: 10) == 7)
    }

    @Test
    func dueBackoffHasZeroDelay() {
        var head = QueuedRequest(makeCreateProfileRequest())
        let now = wallClock.now()
        head.recordRetryableFailure(retryAfter: 37, now: now)

        #expect(nextFlushDelay(head: head, now: now.addingTimeInterval(37), flushInterval: 10) == 0)
        #expect(nextFlushDelay(head: head, now: now.addingTimeInterval(500), flushInterval: 10) == 0)
    }

    // MARK: - Scheduling through the queue

    @Test
    func backoffSleepsItsExactDelay() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 37))])
        enqueueOne()
        let queue = makeQueue(spy)

        await queue.flushNow()
        await queue.start()

        #expect(gated.waitForRequested(atLeast: 1))
        #expect(gated.requested.first == 37)
        await queue.stop()
    }

    @Test
    func backoffBelowFlushIntervalIsFloored() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 3))])
        enqueueOne()
        await makeQueue(spy).flushNow()

        #expect(headDelay == FlushConstants.wifiFlushInterval)
    }

    @Test
    func cellularFloorIsThirtySeconds() async {
        let spy = SendSpy(results: [networkFailure])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.networkConnectivityChanged(.reachableViaWWAN)

        await queue.flushNow()

        #expect(headDelay == FlushConstants.cellularFlushInterval)
        await queue.stop()
    }

    @Test
    func offlineFailureRecordsFiniteDelayAndRetriesAfterReconnect() async {
        let spy = SendSpy(results: [networkFailure, .success(Data())])
        enqueueOne()
        let queue = makeQueue(spy)

        await queue.flushNow()
        await queue.networkConnectivityChanged(.notReachable)
        #expect(headDelay == FlushConstants.wifiFlushInterval)

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        #expect(gated.waitForRequested(atLeast: 1))
        wallClock.advance(by: FlushConstants.wifiFlushInterval)
        gated.releaseOneTick()
        #expect(gated.waitForRequested(atLeast: 2))

        #expect(spy.sentAttempts == [1, 2])
        await queue.stop()
    }

    @Test
    func escalationIsNotPinnedAtFirstAttempt() async throws {
        let spy = SendSpy(results: [networkFailure])
        enqueueOne()
        let queue = makeQueue(spy)
        var delays: [TimeInterval] = []

        for _ in 1...5 {
            await queue.flushNow()
            let delay = try #require(headDelay)
            delays.append(delay)
            wallClock.advance(by: delay)
        }

        #expect(delays == [10, 10, 10, 16, 32])
    }

    @Test
    func backoffExpiredWhileStoppedFiresOnStart() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 37)), .success(Data())])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.flushNow()
        wallClock.advance(by: 60)

        await queue.start()
        #expect(gated.waitForRequested(atLeast: 1))
        #expect(gated.requested.first == 0)
        gated.releaseOneTick()
        #expect(gated.waitForRequested(atLeast: 2))

        #expect(spy.sentAttempts == [1, 2])
        await queue.stop()
    }

    @Test
    func dueBackoffWithoutApiKeyDoesNotSpin() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 37))])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.flushNow()
        wallClock.advance(by: 60)
        SDKConfigStore.shared.reset()

        await queue.start()
        #expect(gated.waitForRequested(atLeast: 1))
        #expect(gated.requested.first == FlushConstants.wifiFlushInterval)
        await queue.stop()
    }

    @Test
    func oneHourTransportOutageStaysWithinAttemptBudget() async {
        let spy = SendSpy(results: [networkFailure])
        enqueueOne()
        let queue = makeQueue(spy)
        let end = wallClock.now().addingTimeInterval(3600)

        while wallClock.now() < end {
            await queue.flushNow()
            let delay = nextFlushDelay(
                head: QueueStore.shared.head,
                now: wallClock.now(),
                flushInterval: FlushConstants.wifiFlushInterval
            )
            wallClock.advance(by: max(delay, 1))
        }

        #expect(spy.sentIds.count <= 25)
        #expect(QueueStore.shared.requests.map(\.id) == ["r"])
    }
}
#endif
