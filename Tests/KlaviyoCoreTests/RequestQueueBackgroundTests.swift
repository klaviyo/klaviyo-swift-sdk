//
//  RequestQueueBackgroundTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import XCTest

final class RequestQueueBackgroundTests: RequestQueueTestCase {
    private var disk: WriteSpyDiskIO!
    private var tasks: FakeBackgroundTasks!
    private var manual: ManualSleepClock!

    override func setUp() {
        super.setUp()
        disk = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: disk))
        tasks = FakeBackgroundTasks()
        manual = ManualSleepClock()
    }

    private func enqueue(_ ids: String...) {
        ids.forEach { QueueStore.shared.enqueue(makeCreateProfileRequest(id: $0), persist: .synchronous) }
    }

    private func makeQueue(send: @escaping RequestQueue.Send) -> RequestQueue {
        RequestQueue(clock: manual.clock, send: send, backgroundTasks: tasks.runner)
    }

    private func startParkedDrain(_ queue: RequestQueue, started: XCTestExpectation) async -> Task<Void, Never> {
        await queue.enterBackground()
        let drain = Task { await queue.backgroundDrain() }
        await fulfillment(of: [started], timeout: 2)
        return drain
    }

    // MARK: - Drain

    func testDrainSendsFifoAndPersistsAfterEachSend() async {
        enqueue("a", "b", "c")
        let disk = disk!
        let snapshots = Snapshots()
        let queue = makeQueue { _, _ in
            snapshots.append(disk.stored.map(\.id))
            return .success(Data())
        }
        await queue.enterBackground()

        await queue.backgroundDrain()

        XCTAssertEqual(snapshots.values, [["a", "b", "c"], ["b", "c"], ["c"]],
                       "each send must find the earlier ones already gone from disk")
        XCTAssertTrue(disk.stored.isEmpty)
        XCTAssertEqual(tasks.begins, 1)
        XCTAssertEqual(tasks.ends, 1)
    }

    func testKillMidDrainKeepsLeasedRequestsOnDisk() async {
        enqueue("a", "b")
        let started = expectation(description: "send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)

        let drain = await startParkedDrain(queue, started: started)

        let rehydrated = disk.stored.map(\.id)
        XCTAssertEqual(rehydrated, ["a", "b"], "a kill now must re-send both, not lose them")
        spy.release()
        await drain.value
    }

    // MARK: - Expiry

    func testExpiryMidSendRestoresLeaseWithoutWaitingOnNetwork() async {
        enqueue("a", "b")
        let started = expectation(description: "send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)

        tasks.expire()
        await drain.value // returns although the parked send never did

        XCTAssertEqual(tasks.ends, 1)
        XCTAssertEqual(disk.stored.map(\.id), ["a", "b"])
        let entries = QueueStore.shared.entries
        XCTAssertEqual(entries.map(\.id), ["a", "b"])
        XCTAssertTrue(entries.allSatisfy { $0.attempts == 0 && $0.nextAttemptAt == nil },
                      "expiry must not burn an attempt or set a backoff")
        spy.release()
    }

    func testLateReturnAfterExpiryIsDiscarded() async {
        enqueue("a", "b")
        let started = expectation(description: "send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)
        tasks.expire()
        await drain.value

        spy.release() // the zombie send reports success late
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a", "b"], "a late success must not dequeue")
        XCTAssertEqual(disk.stored.map(\.id), ["a", "b"])
    }

    func testExpiryWithNothingInFlightBeginsNoTask() async {
        let queue = makeQueue(send: SendSpy().send)
        await queue.enterBackground()

        await queue.backgroundDrain()

        XCTAssertEqual(tasks.begins, 0)
        tasks.expire() // no task: must be a harmless no-op
    }

    func testCancelledSendReportingCancellationErrorIsKept() async {
        enqueue("a")
        let started = expectation(description: "send parked")
        let queue = makeQueue { _, _ in
            await withTaskCancellationHandler {
                started.fulfill()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return .failure(.networkError(CancellationError()))
            } onCancel: {}
        }
        let flush = Task { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2)

        await queue.stop()
        flush.cancel()
        await flush.value

        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a"], "a cancelled send must never drop the request")
        XCTAssertEqual(disk.stored.map(\.id), ["a"])
    }

    // MARK: - Foreground, terminate, cycles

    func testForegroundMidDrainLetsDrainFinish() async {
        enqueue("a", "b")
        let started = expectation(description: "send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)

        await queue.start()
        spy.release()
        await drain.value

        XCTAssertEqual(spy.sentIds, ["a", "b"], "no cancel and no duplicate of the in-flight request")
        XCTAssertTrue(disk.stored.isEmpty)
        XCTAssertEqual(tasks.begins, tasks.ends)
        await queue.stop()
    }

    func testTerminateRestoresLeaseSynchronouslyWithoutTask() async {
        enqueue("a", "b")
        let started = expectation(description: "send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let flush = Task { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2)

        await queue.stop()

        XCTAssertEqual(disk.stored.map(\.id), ["a", "b"])
        XCTAssertEqual(tasks.begins, 0)
        spy.release()
        await flush.value
    }

    func testRapidBackgroundForegroundCyclesLeakNoTasks() async {
        let spy = SendSpy()
        let queue = makeQueue(send: spy.send)
        for index in 0..<10 {
            if index == 0 { enqueue("a", "b") }
            await queue.enterBackground()
            await queue.backgroundDrain()
            await queue.start()
        }

        XCTAssertEqual(spy.sentIds, ["a", "b"], "one drain per backgrounding, nothing re-sent")
        XCTAssertEqual(tasks.begins, 1, "empty cycles must not begin a task")
        XCTAssertEqual(tasks.begins, tasks.ends)
        await queue.stop()
    }

    func testOfflineAndPreInitBeginNoTask() async {
        enqueue("a")
        let spy = SendSpy()
        let queue = makeQueue(send: spy.send)
        await queue.networkConnectivityChanged(.notReachable)
        await queue.enterBackground()

        await queue.backgroundDrain()
        SDKConfigStore.shared.reset()
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        await queue.backgroundDrain()

        XCTAssertEqual(tasks.begins, 0)
        XCTAssertTrue(spy.sentIds.isEmpty)
    }

    func testDeniedTaskStillDrainsBestEffort() async {
        enqueue("a")
        tasks.deny = true
        let spy = SendSpy()
        let queue = makeQueue(send: spy.send)
        await queue.enterBackground()

        await queue.backgroundDrain()

        XCTAssertEqual(spy.sentIds, ["a"])
    }

    // MARK: - Backoff and reachability

    func testBackoffAtBackgroundTimeSendsNothingAndKeepsBacklog() async {
        enqueue("a", "b")
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 60))])
        let queue = makeQueue(send: spy.send)
        await queue.flushNow() // "a" now waits out its own backoff
        await queue.enterBackground()

        await queue.backgroundDrain()

        XCTAssertEqual(spy.sentIds, ["a"], "the backoff head blocks the drain")
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a", "b"])
        XCTAssertEqual(QueueStore.shared.entries.first?.attempts, 1, "no extra attempt or decrement")
        XCTAssertEqual(tasks.begins, 0)
    }

    func testReachabilityWhileBackgroundedDoesNotRestartLoop() async {
        enqueue("a")
        let spy = SendSpy()
        let queue = makeQueue(send: spy.send)
        await queue.enterBackground()

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(spy.sentIds.isEmpty, "a reconnect must not flush while backgrounded")
        await queue.networkConnectivityChanged(.notReachable)
        await queue.backgroundDrain()
        XCTAssertEqual(tasks.begins, 0)
    }

    // MARK: - Watchdog

    func testStalledRequestIsPutBackAndTheRestStillSend() async {
        enqueue("a", "b", "c")
        let started = expectation(description: "first send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)
        XCTAssertTrue(manual.waitForRequested(atLeast: 1))

        manual.fireAll() // the 10s budget elapses for "a"
        await drain.value

        XCTAssertEqual(manual.requested.first, FlushConstants.backgroundSendTimeout)
        XCTAssertEqual(spy.sentIds, ["a", "b", "c"], "later requests still go out in the same drain")
        let entries = QueueStore.shared.entries
        XCTAssertEqual(entries.map(\.id), ["a"], "only the stalled request remains, untouched")
        XCTAssertEqual(entries.first?.attempts, 0)
        XCTAssertNil(entries.first?.nextAttemptAt)
        XCTAssertEqual(disk.stored.map(\.id), ["a"])
        XCTAssertEqual(tasks.ends, 1)
        spy.release()
    }
}

private final class Snapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [[String]] = []
    var values: [[String]] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ value: [String]) { lock.lock(); _values.append(value); lock.unlock() }
}
