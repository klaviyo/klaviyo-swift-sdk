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

    // MARK: - Priority flush

    func testFlushNowWhileActiveBeginsNoTask() async {
        enqueue("a")
        let spy = SendSpy()
        let queue = makeQueue(send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["a"])
        XCTAssertEqual(tasks.begins, 0)
    }

    func testFlushNowWhileBackgroundedOrInactiveTakesOwnTask() async {
        tasks.appActive = false
        enqueue("a")
        let spy = SendSpy()
        let queue = makeQueue(send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["a"])
        XCTAssertEqual(tasks.begins, 1)
        XCTAssertEqual(tasks.ends, 1)
    }

    func testPriorityFlushExpiringFirstDoesNotAbortMainDrain() async {
        enqueue("a", "b")
        let started = expectation(description: "drain send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)
        tasks.appActive = false
        let priority = Task { await queue.flushNow() }
        XCTAssertTrue(tasks.waitForBegins(atLeast: 2))

        tasks.expire(index: 1) // the priority task's deadline arrives first
        await priority.value // returns although the main drain's send is still parked
        spy.release()
        await drain.value

        XCTAssertEqual(spy.sentIds, ["a", "b"], "the main drain must run to completion")
        XCTAssertTrue(disk.stored.isEmpty)
        XCTAssertEqual(tasks.ends, 2)
    }

    func testMainDrainExpiringDoesNotCancelPriorityOwnedFlush() async {
        tasks.appActive = false
        enqueue("a")
        let started = expectation(description: "priority send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let priority = Task { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2)
        await queue.enterBackground()
        let drain = Task { await queue.backgroundDrain() }
        XCTAssertTrue(tasks.waitForBegins(atLeast: 2))

        tasks.expire(index: 1) // the drain's task expires; the priority flush owns the running send
        await drain.value

        XCTAssertEqual(disk.stored.map(\.id), ["a"], "still leased on disk, not lost")
        spy.release()
        await priority.value
        XCTAssertTrue(disk.stored.isEmpty, "the priority flush completed its send")
    }

    func testWifiToCellularSwitchWhileBackgroundedKeepsRetryDeadline() async {
        enqueue("a", "b")
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 60))])
        let queue = makeQueue(send: spy.send)
        await queue.enterBackground()
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        await queue.flushNow() // "a" now waits out its own backoff
        let deadline = QueueStore.shared.head?.nextAttemptAt
        XCTAssertNotNil(deadline)

        await queue.networkConnectivityChanged(.reachableViaWWAN)

        XCTAssertEqual(QueueStore.shared.head?.nextAttemptAt, deadline, "a network switch must keep the backoff")
        XCTAssertEqual(QueueStore.shared.head?.isAwaitingRetry(at: environment.date()), true)
    }

    func testStaleWaitBudgetDoesNotAbandonALaterFlush() async {
        tasks.appActive = false
        enqueue("a")
        let started = expectation(description: "first send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let first = Task { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await queue.flushNow() } // waits on the parked flush under its own budget
        XCTAssertTrue(manual.waitForRequested(atLeast: 2))
        enqueue("b") // queued before the first flush ends, so the second scope's flush is sure to send it

        spy.release()
        await first.value
        manual.fire(requestIndex: 1) // only the second scope's wait budget on the finished flush elapses
        await second.value

        XCTAssertEqual(spy.sentIds, ["a", "b"])
        XCTAssertTrue(disk.stored.isEmpty, "the later flush must complete, not be abandoned")
    }

    func testAbandonWithStaleGenerationLeavesALaterFlushRunning() async {
        enqueue("a")
        let parked = ParkedSends()
        let queue = makeQueue { request, _ in
            await parked.park(request.id)
            return .success(Data())
        }
        let first = Task { await queue.flushNow() }
        XCTAssertTrue(parked.waitForSends(atLeast: 1))
        let stale = await queue.currentFlushGeneration
        parked.releaseAll()
        await first.value
        enqueue("b")
        let second = Task { await queue.flushNow() }
        XCTAssertTrue(parked.waitForSends(atLeast: 2))
        let hasActive = await queue.hasActiveFlush
        XCTAssertTrue(hasActive)

        await queue.abandonActiveFlush(ifGeneration: stale)

        let stillActive = await queue.hasActiveFlush
        XCTAssertTrue(stillActive, "a stale generation must not abandon the later flush")
        XCTAssertEqual(parked.sent, ["a", "b"], "the later request is sent exactly once")
        let current = await queue.currentFlushGeneration
        await queue.abandonActiveFlush(ifGeneration: current)
        let afterMatch = await queue.hasActiveFlush
        XCTAssertFalse(afterMatch, "the matching generation does abandon")
        XCTAssertEqual(disk.stored.map(\.id), ["b"], "the abandoned lease is back on disk")
        parked.releaseAll()
        await second.value
    }

    // MARK: - Watchdog

    func testHungForegroundFlushIsBoundedThenDrainContinues() async {
        enqueue("a", "b")
        let started = expectation(description: "foreground send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let foreground = Task { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2)
        await queue.enterBackground()
        let drain = Task { await queue.backgroundDrain() }
        XCTAssertTrue(manual.waitForRequested(atLeast: 1))

        manual.fireAll() // the bounded wait on the hung foreground send elapses
        await drain.value

        XCTAssertEqual(manual.requested.first, FlushConstants.backgroundSendTimeout)
        XCTAssertEqual(tasks.ends, 1)
        spy.release()
        await foreground.value
        XCTAssertEqual(Set(QueueStore.shared.entries.map(\.id)).union(disk.stored.map(\.id)), Set(disk.stored.map(\.id)),
                       "nothing may exist only in memory")
    }

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

    func testStalledHeadsComeBackInOriginalOrder() async {
        enqueue("a", "b", "c")
        let log = SentLog()
        let queue = makeQueue { request, _ in
            let id = request.id
            log.append(id)
            if log.stalling.contains(id) {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // ignores the budget until cancelled
            }
            return .success(Data())
        }
        log.stalling = ["a", "b"]
        await queue.enterBackground()
        let drain = Task { await queue.backgroundDrain() }
        XCTAssertTrue(manual.waitForRequested(atLeast: 1))
        manual.fireAll() // "a" stalls
        XCTAssertTrue(manual.waitForRequested(atLeast: 2))
        manual.fireAll() // "b" stalls
        await drain.value
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a", "b"], "c was sent; a and b keep their order")
        XCTAssertEqual(disk.stored.map(\.id), ["a", "b"])

        log.stalling = []
        await queue.backgroundDrain()

        XCTAssertEqual(log.values, ["a", "b", "c", "a", "b"], "the next drain sends a before b")
    }

    func testStaleExpiryFromAnEarlierDrainDoesNotCancelTheCurrentOne() async {
        enqueue("a")
        let log = SentLog()
        let queue = makeQueue { request, _ in
            log.append(request.id)
            while request.id == "c", !log.released { try? await Task.sleep(nanoseconds: 10_000_000) }
            return .success(Data())
        }
        await queue.enterBackground()
        await queue.backgroundDrain() // drain one finishes; its expiry handler is still registered
        enqueue("c", "d")
        let drain = Task { await queue.backgroundDrain() }
        XCTAssertTrue(log.waitForSends(atLeast: 2))

        tasks.expire(index: 0) // a late expiry notice for drain one
        try? await Task.sleep(nanoseconds: 100_000_000)
        log.released = true
        await drain.value

        XCTAssertEqual(log.values, ["a", "c", "d"], "drain two must run to completion")
        XCTAssertTrue(QueueStore.shared.entries.isEmpty)
        XCTAssertTrue(disk.stored.isEmpty)
    }
}

private final class Snapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [[String]] = []
    var values: [[String]] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ value: [String]) { lock.lock(); _values.append(value); lock.unlock() }
}

private final class SentLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    private var _stalling: Set<String> = []
    private var _released = false
    var values: [String] { lock.lock(); defer { lock.unlock() }; return _values }
    var stalling: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return _stalling }
        set { lock.lock(); _stalling = newValue; lock.unlock() }
    }

    var released: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _released }
        set { lock.lock(); _released = newValue; lock.unlock() }
    }

    func append(_ id: String) { lock.lock(); _values.append(id); lock.unlock() }
    func waitForSends(atLeast count: Int, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if values.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return values.count >= count
    }
}

private final class ParkedSends: @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [String] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var sent: [String] { lock.lock(); defer { lock.unlock() }; return _sent }

    func park(_ id: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            _sent.append(id)
            continuations.append(continuation)
            lock.unlock()
        }
    }

    /// Resumes the sends parked so far; later sends park again.
    func releaseAll() {
        lock.lock()
        let all = continuations
        continuations = []
        lock.unlock()
        all.forEach { $0.resume() }
    }

    func waitForSends(atLeast count: Int, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if sent.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return sent.count >= count
    }
}
