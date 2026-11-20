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
        RequestQueue(clock: manual.clock, send: send, willDrain: nil, backgroundTasks: tasks.runner)
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

    func testEmptyDrainEndsItsTaskAtOnce() async {
        let queue = makeQueue(send: SendSpy().send)
        await queue.enterBackground()

        await queue.backgroundDrain()

        XCTAssertEqual(tasks.begins, 1)
        XCTAssertEqual(tasks.ends, 1, "an empty queue costs only a begin and end pair")
        tasks.expire() // already ended: must be a harmless no-op
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

        flush.cancel() // only the caller is cancelled: no stop(), so the generation stays current
        await flush.value

        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a"], "a cancelled send must never drop the request")
        XCTAssertEqual(QueueStore.shared.entries.first?.attempts, 0, "a cancelled send is not an attempt")
        XCTAssertEqual(disk.stored.map(\.id), ["a"])
    }

    func testCancelledCallerStopsTheDrainBetweenSends() async {
        enqueue("a", "b")
        let started = expectation(description: "send parked")
        let spy = SendSpy(parkFirstCall: true, started: started) // ignores cancellation, like a real send
        let queue = makeQueue(send: spy.send)
        let flush = Task { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2)

        flush.cancel()
        spy.release() // a succeeds after the caller was cancelled
        await flush.value

        XCTAssertEqual(spy.sentIds, ["a"], "b must not start once the caller is cancelled")
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["b"])
        XCTAssertEqual(disk.stored.map(\.id), ["b"])
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
        XCTAssertEqual(tasks.begins, 10, "each backgrounding begins one task, even when empty")
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
        XCTAssertEqual(tasks.begins, tasks.ends, "the task must be ended when nothing is sent")
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

    func testFlushStartedAfterAnEarlierWaitStaysActive() async {
        enqueue("a")
        let parked = ParkedSends()
        let queue = makeQueue { request, _ in
            await parked.park(request.id)
            return .success(Data())
        }
        let first = Task { await queue.flushNow() } // a foreground flush: no budget of its own
        XCTAssertTrue(parked.waitForSends(atLeast: 1))
        tasks.appActive = false
        let second = Task { await queue.flushNow() } // waits on the parked flush under its own budget
        XCTAssertTrue(manual.waitForRequested(atLeast: 1))
        enqueue("b")
        parked.releaseAll() // the first flush ends; the second scope starts its own flush and parks on b
        await first.value
        XCTAssertTrue(parked.waitForSends(atLeast: 2))

        let active = await queue.hasActiveFlush
        XCTAssertTrue(active, "the flush started after the wait must not be abandoned by it")
        parked.releaseAll()
        await second.value
        XCTAssertEqual(parked.sent, ["a", "b"])
        XCTAssertTrue(disk.stored.isEmpty)
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
        XCTAssertEqual(spy.sentIds, ["a", "a", "b"], "the hung send is put back and sent again, then b")
        XCTAssertTrue(QueueStore.shared.entries.isEmpty)
        XCTAssertTrue(disk.stored.isEmpty)
        spy.release()
        await foreground.value
        XCTAssertEqual(spy.sentIds, ["a", "a", "b"], "the late success must change nothing")
        XCTAssertTrue(QueueStore.shared.entries.isEmpty)
        XCTAssertTrue(disk.stored.isEmpty)
    }

    func testStalledRequestStopsTheDrainAndKeepsOrder() async {
        enqueue("a", "b", "c")
        let started = expectation(description: "first send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)
        XCTAssertTrue(manual.waitForRequested(atLeast: 1))

        manual.fireAll() // the 10s budget elapses for "a"
        await drain.value

        XCTAssertEqual(manual.requested.first, FlushConstants.backgroundSendTimeout)
        XCTAssertEqual(spy.sentIds, ["a"], "nothing behind a stalled request may be sent")
        let entries = QueueStore.shared.entries
        XCTAssertEqual(entries.map(\.id), ["a", "b", "c"], "order is unchanged")
        XCTAssertEqual(entries.first?.attempts, 0, "a stall records no attempt")
        XCTAssertNil(entries.first?.nextAttemptAt, "a stall adds no backoff of its own")
        XCTAssertEqual(disk.stored.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(tasks.ends, 1)
        spy.release()
    }

    func testLaterRequestCannotOvertakeAStalledOne() async {
        enqueue("a", "b")
        let started = expectation(description: "first send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)
        XCTAssertTrue(manual.waitForRequested(atLeast: 1))
        manual.fireAll()
        await drain.value

        XCTAssertEqual(spy.sentIds, ["a"], "b must not be sent while a is stalled")
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a", "b"])

        await queue.backgroundDrain() // the retry starts again from the stalled head

        XCTAssertEqual(spy.sentIds, ["a", "a", "b"], "b only ever goes out after a")
        spy.release()
    }

    func testBackgroundDrainFoldsStagedWorkIntoAnEmptyQueue() async {
        let spy = SendSpy()
        let staged = makeCreateProfileRequest(id: "staged")
        let folded = FoldOnce()
        let queue = RequestQueue(
            clock: manual.clock,
            send: spy.send,
            willDrain: { if folded.take() { QueueStore.shared.enqueue(staged, persist: .synchronous) } },
            backgroundTasks: tasks.runner
        )
        await queue.enterBackground()

        await queue.backgroundDrain()

        XCTAssertEqual(spy.sentIds, ["staged"], "staged work must go out even when the queue was empty")
        XCTAssertTrue(disk.stored.isEmpty)
        XCTAssertEqual(tasks.begins, 1)
    }

    func testPriorityWaitLeavesABudgetedDrainAlone() async {
        enqueue("a")
        let started = expectation(description: "drain send parked")
        let spy = SendSpy(parkFirstCall: true, started: started)
        let queue = makeQueue(send: spy.send)
        let drain = await startParkedDrain(queue, started: started)
        tasks.appActive = false
        let priority = Task { await queue.flushNow() }
        XCTAssertTrue(tasks.waitForBegins(atLeast: 2))
        try? await Task.sleep(nanoseconds: 100_000_000)

        let active = await queue.hasActiveFlush
        XCTAssertTrue(active, "a flush with its own budget must be left to it")
        XCTAssertEqual(disk.stored.map(\.id), ["a"])
        spy.release()
        await drain.value
        await priority.value
        XCTAssertEqual(spy.sentIds, ["a"])
        XCTAssertTrue(disk.stored.isEmpty)
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

    // MARK: - Waiting on an active flush

    func testPriorityRequestQueuedDuringABudgetedDrainIsSentBeforeTheTaskEnds() async {
        enqueue("a")
        let parked = ParkedSends()
        let queue = makeQueue { request, _ in
            await parked.park(request.id)
            return .success(Data())
        }
        await queue.enterBackground()
        let drain = Task { await queue.backgroundDrain() }
        XCTAssertTrue(parked.waitForSends(atLeast: 1))
        tasks.appActive = false
        let priority = Task { await queue.flushNow() }
        XCTAssertTrue(tasks.waitForBegins(atLeast: 2))
        for _ in 0..<50 { _ = await queue.hasActiveFlush } // let the priority scope reach its wait
        enqueue("b") // arrives after the drain leased its batch
        XCTAssertEqual(parked.sent, ["a"], "b waits for the priority pass while a is parked")

        parked.releaseAll()
        XCTAssertTrue(parked.waitForSends(atLeast: 2), "b must go out in the priority pass")
        parked.releaseAll()
        await drain.value
        await priority.value

        XCTAssertEqual(parked.sent, ["a", "b"])
        XCTAssertEqual(manual.requested, [FlushConstants.backgroundSendTimeout, FlushConstants.backgroundSendTimeout],
                       "one budget per send (a, b) and no timed wait on a budgeted flush")
        XCTAssertTrue(disk.stored.isEmpty)
        XCTAssertEqual(tasks.ends, 2)
    }

    func testBackgroundDrainDoesNotAbandonABudgetedPriorityFlush() async {
        enqueue("a")
        let parked = ParkedSends()
        let queue = makeQueue { request, _ in
            await parked.park(request.id)
            return .success(Data())
        }
        tasks.appActive = false
        let priority = Task { await queue.flushNow() }
        XCTAssertTrue(parked.waitForSends(atLeast: 1))
        await queue.enterBackground()
        let drain = Task { await queue.backgroundDrain() }
        XCTAssertTrue(tasks.waitForBegins(atLeast: 2))
        try? await Task.sleep(nanoseconds: 100_000_000)
        manual.fire(requestIndex: 1) // the old bounded wait; nothing to fire once the wait is unbounded
        try? await Task.sleep(nanoseconds: 100_000_000)

        let active = await queue.hasActiveFlush
        XCTAssertTrue(active, "a flush with its own budget must be left to it")
        XCTAssertEqual(parked.sent, ["a"], "a must not be restored and sent again")
        parked.releaseAll()
        try? await Task.sleep(nanoseconds: 50_000_000)
        parked.releaseAll()
        await priority.value
        await drain.value
        XCTAssertEqual(parked.sent, ["a"])
        XCTAssertTrue(disk.stored.isEmpty)
    }

    func testCancellingFlushNowCancelsThePriorityScopeAndRestoresTheLease() async {
        enqueue("a")
        let parked = ParkedSends()
        let queue = makeQueue { request, _ in
            await parked.park(request.id)
            return .success(Data())
        }
        tasks.appActive = false
        let finished = expectation(description: "flushNow returned")
        let priority = Task {
            await queue.flushNow()
            finished.fulfill()
        }
        XCTAssertTrue(parked.waitForSends(atLeast: 1))

        priority.cancel()
        await fulfillment(of: [finished], timeout: 2)

        let active = await queue.hasActiveFlush
        XCTAssertFalse(active)
        XCTAssertEqual(disk.stored.map(\.id), ["a"], "the lease must be back in the queue")
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a"], "a must be pending again, not leased")
        XCTAssertEqual(tasks.ends, 1)
        parked.releaseAll()
    }

    func testConcurrentBackgroundDrainsBeginOneTask() async {
        enqueue("a")
        let gate = ParkedSends()
        let once = FoldOnce()
        let spy = SendSpy()
        let queue = RequestQueue(
            clock: manual.clock,
            send: spy.send,
            willDrain: { if once.take() { await gate.park("w") } },
            backgroundTasks: tasks.runner
        )
        await queue.enterBackground()
        let first = Task { await queue.backgroundDrain() }
        XCTAssertTrue(gate.waitForSends(atLeast: 1))
        let entered = Flag()
        let returned = Flag()
        let second = Task {
            entered.set()
            await queue.backgroundDrain()
            returned.set()
        }
        XCTAssertTrue(entered.wait())
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(returned.isSet, "the second caller must wait on the first drain")

        gate.releaseAll()
        await first.value
        await second.value

        XCTAssertTrue(returned.isSet)
        XCTAssertEqual(tasks.begins, 1, "the second caller must join the first drain")
        XCTAssertEqual(spy.sentIds, ["a"])
    }

    func testBackgroundTaskBeginsBeforeStagedWorkIsFolded() async {
        enqueue("a")
        let seen = SentLog()
        let tasks = tasks!
        let queue = RequestQueue(
            clock: manual.clock,
            send: SendSpy().send,
            willDrain: { seen.append("begins=\(tasks.begins)") },
            backgroundTasks: tasks.runner
        )
        await queue.enterBackground()

        await queue.backgroundDrain()

        XCTAssertEqual(seen.values, ["begins=1"], "the task must begin first, and willDrain runs once")
    }

    func testPriorityExpiryBeforeBeginReturnsSendsNothing() async {
        enqueue("a")
        let spy = SendSpy()
        let ended = Flag()
        let box = QueueBox()
        let runner = BackgroundTaskRunner(begin: { _, onExpire in
            onExpire()
            // Return only once the queue has recorded the expiry (bounded, no fixed sleep).
            for _ in 0..<2000 {
                if let queue = box.queue, await queue.pendingStartExpiries > 0 { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            return BackgroundTaskHandle { ended.set() }
        }, isAppActive: { false })
        let queue = RequestQueue(clock: manual.clock, send: spy.send, willDrain: nil, backgroundTasks: runner)
        box.queue = queue

        await queue.flushNow()

        XCTAssertTrue(spy.sentIds.isEmpty, "an expired task must not send")
        XCTAssertTrue(ended.isSet)
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["a"])
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
    private var _released = false
    var values: [String] { lock.lock(); defer { lock.unlock() }; return _values }
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

private final class FoldOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; defer { done = true }; return !done }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
    func wait(timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !isSet { Thread.sleep(forTimeInterval: 0.01) }
        return isSet
    }
}

private final class QueueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _queue: RequestQueue?
    var queue: RequestQueue? {
        get { lock.lock(); defer { lock.unlock() }; return _queue }
        set { lock.lock(); _queue = newValue; lock.unlock() }
    }
}
