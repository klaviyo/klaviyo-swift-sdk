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

    func testWifiToCellularSwitchAlsoResets() async {
        let spy = SendSpy(results: [networkFailure, .failure(.rateLimitError(backOff: 120)), .success(Data())])
        enqueueOne()
        let queue = makeQueue(spy)
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        wallClock.advance(by: FlushConstants.wifiFlushInterval)
        await queue.flushNow()
        XCTAssertEqual(headDelay, 120)

        await queue.networkConnectivityChanged(.reachableViaWWAN)
        XCTAssertTrue(gated.waitForRequested(atLeast: 2))

        XCTAssertEqual(spy.sentAttempts, [1, 2, 3])
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
