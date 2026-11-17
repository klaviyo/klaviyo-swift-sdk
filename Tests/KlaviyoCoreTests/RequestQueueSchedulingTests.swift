//
//  RequestQueueSchedulingTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import XCTest

/// XCTest (serial) because `RequestQueue` reads the global `environment` and `QueueStore.shared`.
final class RequestQueueSchedulingTests: RequestQueueTestCase {
    private var gated: GatedSleepClock!

    override func setUp() {
        super.setUp()
        gated = GatedSleepClock()
        QueueStore.register(makeQueueStore())
    }

    override func tearDown() {
        gated = nil
        super.tearDown()
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

    func testBackoffSleepsItsExactDelay() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 37))])
        enqueueOne()
        let queue = makeQueue(spy)

        await queue.flushNow()
        await queue.start()

        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        XCTAssertEqual(gated.requested.first, 37)
        await queue.stop()
    }

    func testBackoffBelowFlushIntervalIsFloored() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 3))])
        enqueueOne()
        await makeQueue(spy).flushNow()

        XCTAssertEqual(headDelay, FlushConstants.wifiFlushInterval)
    }

    func testCellularFloorIsThirtySeconds() async {
        let spy = SendSpy(results: [networkFailure])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.networkConnectivityChanged(.reachableViaWWAN)

        await queue.flushNow()

        XCTAssertEqual(headDelay, FlushConstants.cellularFlushInterval)
        await queue.stop()
    }

    func testOfflineFailureRecordsFiniteDelayAndRetriesAfterReconnect() async {
        let spy = SendSpy(results: [networkFailure, .success(Data())])
        enqueueOne()
        let queue = makeQueue(spy)

        await queue.flushNow()
        await queue.networkConnectivityChanged(.notReachable)
        XCTAssertEqual(headDelay, FlushConstants.wifiFlushInterval)

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        wallClock.advance(by: FlushConstants.wifiFlushInterval)
        gated.releaseOneTick()
        XCTAssertTrue(gated.waitForRequested(atLeast: 2))

        XCTAssertEqual(spy.sentAttempts, [1, 2])
        await queue.stop()
    }

    // MARK: - Reconnect

    /// Leaves the head backing off for 120s (well past one tick) with one recorded attempt.
    private func makeBackingOffQueue(_ spy: SendSpy) async -> RequestQueue {
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.flushNow()
        XCTAssertEqual(headDelay, 120)
        return queue
    }

    func testReconnectFlushesWithoutWaitingATickAndKeepsAttempts() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 120)), .success(Data())])
        let queue = await makeBackingOffQueue(spy)
        await queue.networkConnectivityChanged(.notReachable)

        await queue.networkConnectivityChanged(.reachableViaWiFi)

        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        XCTAssertEqual(spy.sentAttempts, [1, 2])
        XCTAssertTrue(QueueStore.shared.requests.isEmpty)
        await queue.stop()
    }

    func testFailureAfterReconnectEscalatesFromKeptAttempts() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 120)), networkFailure])
        let queue = await makeBackingOffQueue(spy)

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))

        XCTAssertEqual(spy.sentAttempts, [1, 2])
        XCTAssertEqual(QueueStore.shared.head?.attempts, 2)
        await queue.stop()
    }

    /// A Wi-Fi/cellular switch while online is not a reconnect: the backoff and countdown stay.
    func testWifiToCellularSwitchKeepsBackoff() async {
        let spy = SendSpy(results: [networkFailure, .failure(.rateLimitError(backOff: 120))])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        wallClock.advance(by: FlushConstants.wifiFlushInterval)
        await queue.flushNow()
        XCTAssertEqual(headDelay, 120)

        await queue.networkConnectivityChanged(.reachableViaWWAN)

        XCTAssertEqual(spy.sentAttempts, [1, 2])
        XCTAssertEqual(headDelay, 120)
        XCTAssertEqual(gated.requested.count, 1, "a switch must not restart the countdown")
        await queue.stop()
    }

    func testReconnectMidFlushClearsBackoffOfLeasedEntries() async {
        let backoff = SendSpy(results: [.failure(.rateLimitError(backOff: 120))])
        enqueueOne()
        await makeQueue(backoff).flushNow()
        QueueStore.shared.enqueue(makePriorityEventRequest(id: "p"), persist: .synchronous)

        let started = expectation(description: "flush parked mid-send")
        let parking = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(parking)
        let flush = Task.detached { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2.0)

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        parking.release()
        await flush.value

        XCTAssertEqual(parking.sentIds, ["p", "r"])
        await queue.stop()
    }

    func testReconnectDuringSuspendedSendFlushesRestoredRequestWithoutATick() async {
        enqueueOne()
        let started = expectation(description: "flush parked mid-send")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(spy)
        let flush = Task.detached { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2.0)

        await queue.networkConnectivityChanged(.notReachable)
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        spy.release()
        await flush.value

        XCTAssertTrue(spy.waitForSends(atLeast: 2))
        XCTAssertEqual(spy.sentIds, ["r", "r"])
        await queue.stop()
    }

    func testReconnectDuringSuspendedRunLoopSendFlushesRestoredRequestWithoutATick() async {
        enqueueOne()
        let started = expectation(description: "run loop parked mid-send")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(spy)
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        await fulfillment(of: [started], timeout: 2.0)

        await queue.networkConnectivityChanged(.notReachable)
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        spy.release()

        XCTAssertTrue(spy.waitForSends(atLeast: 2))
        XCTAssertEqual(spy.sentIds, ["r", "r"])
        await queue.stop()
    }

    func testRepeatedReachableStatusOrSwitchKeepsBackoff() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 120))])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(spy.waitForSends(atLeast: 1))
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        XCTAssertEqual(headDelay, 120)

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        await queue.networkConnectivityChanged(.reachableViaWWAN)

        XCTAssertEqual(spy.sentIds, ["r"])
        XCTAssertEqual(headDelay, 120)
        await queue.stop()
    }

    func testEscalationIsNotPinnedAtFirstAttempt() async throws {
        let spy = SendSpy(results: [networkFailure])
        enqueueOne()
        let queue = makeQueue(spy)
        var delays: [TimeInterval] = []

        for _ in 1...5 {
            await queue.flushNow()
            let delay = try XCTUnwrap(headDelay)
            delays.append(delay)
            wallClock.advance(by: delay)
        }

        XCTAssertEqual(delays, [10, 10, 10, 16, 32])
    }

    func testBackoffExpiredWhileStoppedFiresOnStart() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 37)), .success(Data())])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.flushNow()
        wallClock.advance(by: 60)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        XCTAssertEqual(gated.requested.first, 0)
        gated.releaseOneTick()
        XCTAssertTrue(gated.waitForRequested(atLeast: 2))

        XCTAssertEqual(spy.sentAttempts, [1, 2])
        await queue.stop()
    }

    func testDueBackoffWithoutApiKeyDoesNotSpin() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 37))])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.flushNow()
        wallClock.advance(by: 60)
        SDKConfigStore.shared.reset()

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        XCTAssertEqual(gated.requested.first, FlushConstants.wifiFlushInterval)
        await queue.stop()
    }

    func testDueBackoffWhileOfflineDoesNotSpin() async {
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 37))])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.flushNow()
        wallClock.advance(by: 60)
        await queue.networkConnectivityChanged(.notReachable)

        await queue.start()
        XCTAssertFalse(gated.waitForRequested(atLeast: 1, timeout: 0.3), "no loop runs while offline")
        XCTAssertEqual(spy.sentAttempts, [1])
        await queue.stop()
    }

    func testCancelledResendOfDueHeadWaitsOneInterval() async {
        let spy = SendSpy(results: [networkFailure, .failure(.networkError(URLError(.cancelled)))])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.flushNow()
        wallClock.advance(by: 60)

        await queue.flushNow()
        XCTAssertEqual(spy.sentAttempts, [1, 2], "the due head is resent once and cancelled")
        XCTAssertEqual(QueueStore.shared.entries.map(\.attempts), [1], "a cancel records no attempt")
        XCTAssertEqual(headDelay, FlushConstants.wifiFlushInterval)

        await queue.flushNow()
        XCTAssertEqual(spy.sentAttempts, [1, 2], "no resend before the next interval")
    }

    func testOneHourTransportOutageStaysWithinAttemptBudget() async {
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

        XCTAssertLessThanOrEqual(spy.sentIds.count, 25)
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["r"])
    }
}
