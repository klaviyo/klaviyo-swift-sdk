//
//  RequestQueueTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

@testable import KlaviyoCore
import XCTest

final class RequestQueueTests: XCTestCase {
    private var fileIO: FileIODouble!

    override func setUp() {
        super.setUp()
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
        // An apiKey is required for `flush()` to run (pre-init flushing stays gated).
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "test-api-key"))
    }

    override func tearDown() {
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        fileIO = nil
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

    // MARK: - flush()

    /// `willDrain` runs before the drain, so a request it enqueues is part of the leased batch and
    /// gets sent in this same flush.
    func testWillDrainRunsBeforeDrain() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy()
        let willDrainRequest = makeCreateProfileRequest(id: "from-will-drain")
        let queue = RequestQueue(
            clock: .immediate,
            send: spy.send,
            willDrain: { QueueStore.shared.enqueue(willDrainRequest, persist: .synchronous) }
        )

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["from-will-drain"],
                       "willDrain must run before the drain so its request is sent")
    }

    /// Requests are drained and sent head-first in FIFO order.
    func testDrainsAndSendsInFifoOrder() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy()
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "one"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "two"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "three"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["one", "two", "three"])
    }

    /// An empty queue never calls `send`.
    func testEmptyQueueIsNoOp() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy()
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertTrue(spy.sentIds.isEmpty, "send must not be called for an empty queue")
    }

    /// On a successful `.registerPushToken`, the payload's token (and enablement/background) is
    /// written back to the canonical `IdentityStore`.
    func testRegisterSuccessWritesTokenBackToIdentityStore() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy()
        QueueStore.shared.enqueue(
            makeRegisterPushTokenRequest(
                token: "push-token-abc",
                enablement: .authorized,
                background: .available
            ),
            persist: .synchronous
        )
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(IdentityStore.shared.pushToken?.pushToken, "push-token-abc")
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushEnablement, .authorized)
        XCTAssertEqual(IdentityStore.shared.pushToken?.pushBackground, .available)
    }

    /// With no apiKey set, `flush()` is a no-op: `send` is never called.
    func testNoApiKeySkipsFlush() async {
        SDKConfigStore.shared.reset() // clear the apiKey seeded in setUp
        QueueStore.register(makeQueueStore())
        let spy = SendSpy()
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "one"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertTrue(spy.sentIds.isEmpty, "flush must no-op when no apiKey is set")
    }

    // MARK: - Run loop

    /// `start()` spins up a run loop that requests sleeps of `flushInterval` (wifi default). Using a
    /// gated clock, the loop advances one controlled step at a time, so we assert the requested
    /// duration deterministically rather than an unbounded tick count.
    func testStartTicksAtFlushInterval() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1), "run loop should request its first sleep")
        XCTAssertEqual(gated.requested.first, FlushConstants.wifiFlushInterval)

        // Release one tick; the loop runs the stub flush and re-parks on a second sleep.
        gated.releaseOneTick()
        XCTAssertTrue(gated.waitForRequested(atLeast: 2), "loop should re-request a sleep after a tick")
        XCTAssertEqual(gated.requested[1], FlushConstants.wifiFlushInterval)

        await queue.stop()
    }

    /// `start()` then `stop()` completes without hanging or crashing.
    func testStartThenStopCompletes() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        await queue.stop() // must return promptly
    }

    /// A `start()` after a `stop()` works — the loop can be restarted.
    func testRestartAfterStop() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        await queue.stop()

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 2), "a fresh loop should request another sleep")
        await queue.stop()
    }

    /// With an empty in-flight lease, `stop()` must not prepend anything to the shared store.
    func testStopWithEmptyLeaseDoesNotPrepend() async {
        let diskSpy = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: diskSpy))
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        await queue.stop()

        XCTAssertTrue(diskSpy.savedBatches.isEmpty, "empty lease must not restore anything")
        XCTAssertTrue(diskSpy.stored.isEmpty, "no requests should have been written")
    }

    /// `flushNow()` returns without hanging against an empty queue.
    func testFlushNowReturns() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)
        await queue.flushNow()
    }

    // MARK: - Re-entrancy

    /// A second flush must not clobber an in-flight lease held by a suspended flush. Flush A parks
    /// mid-`send` with its whole batch leased; while it is parked, flush B runs against the now-empty
    /// store and must no-op (guarded by `isFlushing`) WITHOUT draining or dropping anything. When A
    /// resumes it finishes its batch, so every originally-queued request is sent exactly once and the
    /// store is left empty — nothing stranded, nothing lost.
    func testConcurrentFlushDoesNotClobberInFlightLease() async {
        QueueStore.register(makeQueueStore())
        let started = expectation(description: "flush A parked mid-send")
        // ParkingSendSpy equivalent: parkFirstCall=true, default success result.
        let spy = SendSpy(parkFirstCall: true, started: started)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "one"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "two"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        // Flush A: drains ["one", "two"] and parks inside `send` on "one".
        let flushA = Task.detached { await queue.flushNow() }

        // Wait (bounded) until A is parked mid-send with its batch leased.
        await fulfillment(of: [started], timeout: 2.0)

        // Store is now empty (A leased everything). Flush B must no-op without clobbering the lease.
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["one"],
                       "flush B must not drain or re-send anything while A holds the lease")

        // Resume A; it finishes its batch. All originals sent exactly once, in order.
        spy.release()
        await flushA.value

        XCTAssertEqual(spy.sentIds, ["one", "two"],
                       "every queued request is sent exactly once; none lost or duplicated")
        XCTAssertTrue(QueueStore.shared.drainAll().isEmpty,
                      "nothing should be stranded in the store after A completes")
    }

    // MARK: - Failure handling

    /// A transient network error stops the flush and restores the head to the queue (not dropped).
    /// The NEXT flush tick (simulated by a second `flushNow()`) resends it; on success it dequeues.
    /// The attempt number increments across the two sends, proving retry bookkeeping persisted.
    func testNetworkErrorRetriesOnNextTickAndIncrementsCount() async {
        QueueStore.register(makeQueueStore())
        // ScriptedSendSpy equivalent: scripted results consumed in order.
        let spy = SendSpy(results: [
            .failure(.networkError(NSError(domain: "test", code: -1))),
            .success(Data())
        ])
        let request = makeCreateProfileRequest(id: "net-retry")
        QueueStore.shared.enqueue(request, persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        // First tick: network error → restored, not dropped.
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["net-retry"])
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["net-retry"],
                       "network error must restore the request to the queue, not drop it")

        // Second tick: send succeeds → sent again and dequeued. Attempt number incremented.
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["net-retry", "net-retry"], "request resent on the next tick")
        XCTAssertEqual(spy.sentAttempts, [1, 2], "retry count incremented across ticks")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "request dequeued after success")
    }

    /// A rate-limit error sleeps the backoff, then retries the SAME head in place within one flush
    /// (Decision 2: direct sleep). `RecordingSleepClock` returns instantly and records the backoff.
    func testRateLimitSleepsBackoffThenResends() async {
        QueueStore.register(makeQueueStore())
        let recording = RecordingSleepClock()
        let spy = SendSpy(results: [
            .failure(.rateLimitError(backOff: 8)),
            .success(Data())
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "rate"), persist: .synchronous)
        let queue = RequestQueue(clock: recording.clock, send: spy.send)

        await queue.flushNow()

        XCTAssertTrue(recording.requested.contains(8), "backoff of 8s must be slept before resend")
        XCTAssertEqual(spy.sentIds, ["rate", "rate"], "same head retried in place after the sleep")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "request dequeued after successful resend")
    }

    /// A server error behaves like a rate-limit: sleep the backoff, then retry the same head in place.
    func testServerErrorSleepsBackoffThenResends() async {
        QueueStore.register(makeQueueStore())
        let recording = RecordingSleepClock()
        let spy = SendSpy(results: [
            .failure(.serverError(statusCode: 503, backOff: 5)),
            .success(Data())
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "srv"), persist: .synchronous)
        let queue = RequestQueue(clock: recording.clock, send: spy.send)

        await queue.flushNow()

        XCTAssertTrue(recording.requested.contains(5), "server-error backoff must be slept")
        XCTAssertEqual(spy.sentIds, ["srv", "srv"], "same head retried in place after the sleep")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "request dequeued after successful resend")
    }

    /// Once the retry count exceeds `maxRetries` the head is dropped, not resent. The low-retry
    /// endpoint (`maxRetries == 1`) exceeds on the first network error (count → 2).
    func testExceedingMaxRetriesDropsRequest() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [
            .failure(.networkError(NSError(domain: "test", code: -1)))
        ])
        QueueStore.shared.enqueue(makeLowRetryRequest(id: "doomed"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["doomed"], "sent once")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty,
                      "request exceeding maxRetries must be dropped, not restored")
    }

    /// On a retryable failure of the head, the remaining leased requests are restored to the queue
    /// (via `.synchronous` prepend) and the in-memory lease is cleared.
    func testFailureRestoresRemainingLeaseToQueue() async {
        let diskSpy = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: diskSpy))
        let spy = SendSpy(results: [
            .failure(.networkError(NSError(domain: "test", code: -1)))
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "head"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "tail"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["head"], "flush stops at the failing head")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["head", "tail"],
                       "the whole remaining lease is restored to the front of the queue")
        XCTAssertFalse(diskSpy.savedBatches.isEmpty, "restore must persist synchronously")
    }

    /// Exercises the `.retryWithBackoff` EXCEEDED branch. A low-retry endpoint (`maxRetries == 1`)
    /// receives a rate-limit error on its first attempt: `classifyFailure` returns
    /// `.retryWithBackoff(requestCount: 2, ...)`, which exceeds `maxRetries == 1`. The engine must
    /// DROP the head (not restore it) without sleeping the backoff, restore the (now-empty) remaining
    /// lease, and return — leaving the store empty and `send` called exactly once.
    func testExceedingMaxRetriesOnBackoffDropsRequest() async {
        QueueStore.register(makeQueueStore())
        let recording = RecordingSleepClock()
        let spy = SendSpy(results: [
            .failure(.rateLimitError(backOff: 5))
        ])
        QueueStore.shared.enqueue(makeLowRetryRequest(id: "backoff-doomed"), persist: .synchronous)
        let queue = RequestQueue(clock: recording.clock, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["backoff-doomed"], "request sent exactly once before being dropped")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty,
                      "head must be dropped (not restored) when backoff retryCount exceeds maxRetries")
        XCTAssertTrue(recording.requested.isEmpty,
                      "backoff sleep must NOT fire when the exceeded branch exits early")
    }

    /// Exercises the `.dequeue` CONTINUE semantics. Two requests are seeded; the first fails with a
    /// non-retryable error (`.internalError`) which classifies as `.dequeue`. The engine must remove
    /// the first request, CONTINUE the flush loop without stopping, send the second, and dequeue it on
    /// success — leaving the store empty after a single `flushNow()`. This distinguishes the
    /// dequeue+continue path from retry paths that stop+restore the lease.
    func testNonRetryableErrorDequeuesAndContinuesToNextRequest() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [
            .failure(.internalError("non-retryable")),
            .success(Data())
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "bad"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "good"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["bad", "good"],
                       "both requests sent: dequeue+continue moves past the non-retryable failure")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty,
                      "store must be empty: non-retryable dequeued, successor succeeded and dequeued")
    }

    // MARK: - Connectivity

    /// `.reachableViaWiFi` sets `flushInterval = 10.0`: the run loop requests 10-second sleeps.
    func testWiFiConnectivitySetsTenSecondInterval() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1), "loop should request its first sleep")
        XCTAssertEqual(gated.requested.first, FlushConstants.wifiFlushInterval,
                       "WiFi interval must be 10.0 s")

        gated.releaseOneTick()
        XCTAssertTrue(gated.waitForRequested(atLeast: 2), "loop should re-park after one tick")
        XCTAssertEqual(gated.requested[1], FlushConstants.wifiFlushInterval,
                       "second sleep must still be the wifi interval")

        await queue.stop()
    }

    /// `.reachableViaWWAN` sets `flushInterval = 30.0`: the run loop requests 30-second sleeps.
    func testWWANConnectivitySetsThirtySecondInterval() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        await queue.networkConnectivityChanged(.reachableViaWWAN)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1), "loop should request its first sleep")
        XCTAssertEqual(gated.requested.first, FlushConstants.cellularFlushInterval,
                       "WWAN interval must be 30.0 s")

        gated.releaseOneTick()
        XCTAssertTrue(gated.waitForRequested(atLeast: 2), "loop should re-park after one tick")
        XCTAssertEqual(gated.requested[1], FlushConstants.cellularFlushInterval,
                       "second sleep must still be the cellular interval")

        await queue.stop()
    }

    /// `.notReachable` cancels the run loop: no new sleeps are recorded after the call.
    func testNotReachableStopsLoop() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        // Start a loop first so we have something to stop.
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1), "loop should park on its first sleep")

        // Snapshot the recorded-sleep count while the loop is parked on its first sleep.
        let countBeforeStop = gated.requested.count

        // Going offline must cancel the loop.
        await queue.networkConnectivityChanged(.notReachable)

        // Release the parked sleep so the cancelled task can exit cleanly. A live loop would re-park
        // on a fresh sleep here (bumping the count); a cancelled loop records zero new sleeps.
        gated.releaseOneTick()

        // Drive the actor to a quiescent point: this await only returns once the actor has processed
        // any in-flight work, so if the cancelled task were going to re-request a sleep it would have
        // done so by now. No `Thread.sleep`, no timing window.
        await queue.flushNow()

        XCTAssertEqual(gated.requested.count, countBeforeStop,
                       "cancelled loop must not request additional sleeps after .notReachable")
    }

    /// `.notReachable` restores any in-flight lease to `QueueStore` (parity with
    /// `cancelInFlightRequests` in the reducer's connectivity handler).
    /// Strategy: park a flush mid-send so `requestsInFlight` is populated, then call
    /// `networkConnectivityChanged(.notReachable)` — which runs `stop()` — and verify the
    /// synchronous prepend hit the disk spy BEFORE the parked send is released. This confirms the
    /// restore happened as a direct consequence of going offline, not of the flush completing.
    func testNotReachableRestoresInFlightLease() async {
        let diskSpy = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: diskSpy))

        // A parking send spy lets us hold the actor mid-flush so requestsInFlight is populated.
        let started = expectation(description: "flush parked mid-send")
        // ParkingSendSpy equivalent: parkFirstCall=true, default success result.
        let parking = SendSpy(parkFirstCall: true, started: started)

        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "leased"), persist: .synchronous)

        let queue = RequestQueue(clock: .immediate, send: parking.send)

        // Kick off a flush that parks mid-send; the request is now leased from the store.
        let flushTask = Task.detached { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2.0)

        // The store is now empty (the batch is in requestsInFlight). Going offline must call
        // stop() which synchronously prepends the in-flight batch back to the store.
        await queue.networkConnectivityChanged(.notReachable)

        // Assert the restore happened synchronously before we even release the parked send.
        XCTAssertFalse(diskSpy.savedBatches.isEmpty,
                       ".notReachable must restore any in-flight lease to QueueStore synchronously")

        // Release the parked send so the task exits cleanly (stop() cleared requestsInFlight;
        // flush() sees an empty array on resume and the while loop exits without crashing).
        parking.release()
        await flushTask.value
    }

    /// Regression for the join-point guard: `stop()` (from `.notReachable`) can run across the
    /// `await send(...)` suspension point of a `flushNow()`-initiated flush — cancelling `runLoop`
    /// does NOT cancel a `flushNow` flush. `stop()` restores the lease and clears `requestsInFlight`;
    /// when the parked send resumes returning a `.failure`, EVERY outcome branch (not just `.success`)
    /// must bail on the empty lease rather than crash on `removeFirst()`. This proves the guard covers
    /// the failure path: no crash, and the request is preserved in the store (restored by stop(),
    /// neither lost nor double-processed).
    func testStopDuringSendWithFailureOutcomePreservesRequest() async {
        QueueStore.register(makeQueueStore())
        let started = expectation(description: "flush parked mid-send")
        // FailingParkingSendSpy equivalent: first call parks and returns .failure(.internalError),
        // subsequent calls succeed. [X, .success] with "last repeats" gives identical semantics.
        let parking = SendSpy(
            results: [.failure(.internalError("boom")), .success(Data())],
            parkFirstCall: true,
            started: started
        )

        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "leased"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: parking.send)

        // flushNow() leases the batch and parks inside send. Cancelling runLoop won't cancel this.
        let flushTask = Task.detached { await queue.flushNow() }
        await fulfillment(of: [started], timeout: 2.0)

        // Going offline runs stop(): restores the lease to the store and clears requestsInFlight.
        await queue.networkConnectivityChanged(.notReachable)
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["leased"],
                       "stop() must restore the in-flight lease before the parked send resumes")

        // Release the parked send returning .failure. The resumed flush must hit the join-point
        // guard, see the empty lease, and return without crashing on removeFirst().
        parking.release()
        await flushTask.value

        // The request is preserved exactly once: restored by stop(), not dropped by the failure
        // branch, not re-sent (the store still holds it).
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["leased"],
                       "request preserved after stop-during-send with a .failure outcome")
        XCTAssertEqual(parking.sentIds, ["leased"], "the head was sent exactly once, not re-processed")
    }

    /// Regression for the backoff-sleep join-point: `stop()` (from `.notReachable`) can fire while
    /// `flush()` is parked in the backoff `clock.sleep` of the `.retryWithBackoff` not-exceeded
    /// branch. `stop()` restores the lease and clears `requestsInFlight`; when the gated clock is
    /// released the flush's `continue` re-evaluates `requestsInFlight.first`, finds it empty (the
    /// lease was cleared by `stop()`), and exits cleanly — no crash and the request is preserved in
    /// the store (restored by `stop()`, not lost and not double-sent).
    /// Runs 3 times for stability (no wall-clock waits in assertions).
    func testStopDuringBackoffSleepPreservesRequest() async {
        for _ in 1...3 {
            SDKConfigStore.shared.reset()
            IdentityStore.shared.reset()
            QueueStore.resetShared()
            fileIO = FileIODouble()
            environment = fileIO.makeEnvironment()
            SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "test-api-key"))

            let diskSpy = WriteSpyDiskIO()
            QueueStore.register(makeQueueStore(diskIO: diskSpy))

            // A gated clock parks the flush inside the backoff sleep. `flushNow()` only enters one
            // clock.sleep — the backoff — so a gated clock parks there deterministically.
            let gated = GatedSleepClock()

            // Script: first send fails with a rate-limit error (enters backoff), second would succeed
            // but must never be reached because stop() fires while the backoff sleep is parked.
            let spy = SendSpy(results: [
                .failure(.rateLimitError(backOff: 60)),
                .success(Data())
            ])

            QueueStore.shared.enqueue(makeCreateProfileRequest(id: "backoff-parked"), persist: .synchronous)
            let queue = RequestQueue(clock: gated.clock, send: spy.send)

            // Kick off a flushNow() — it sends, gets a rate-limit error, then parks on the backoff
            // sleep. Since flushNow doesn't run the loop, the ONLY clock.sleep is the backoff one.
            let flushTask = Task.detached { await queue.flushNow() }

            // Wait (bounded) until the flush has parked on the backoff sleep.
            XCTAssertTrue(gated.waitForRequested(atLeast: 1, timeout: 2.0),
                          "flush must park on the backoff sleep before we call networkConnectivityChanged")

            // Going offline runs stop(): cancels the loop (no-op here since flushNow is not the
            // loop), restores the in-flight lease to QueueStore, and clears requestsInFlight.
            await queue.networkConnectivityChanged(.notReachable)

            // The restore must have hit disk before we release the sleep.
            XCTAssertFalse(diskSpy.savedBatches.isEmpty,
                           "stop() must restore the in-flight lease to QueueStore synchronously")
            XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["backoff-parked"],
                           "request must be in the store (restored by stop()) before sleep is released")

            // Release the backoff sleep. The flush's `continue` re-checks `requestsInFlight.first`,
            // finds it empty (cleared by stop()), and exits the while loop cleanly — no crash, no
            // second send.
            gated.releaseOneTick()
            await flushTask.value

            // The request is preserved exactly once: restored by stop(), not dropped, not re-sent.
            XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["backoff-parked"],
                           "request preserved after stop-during-backoff-sleep: in store, not lost")
            XCTAssertEqual(spy.sentIds, ["backoff-parked"],
                           "head sent exactly once; no second send after the sleep was released")
        }
    }

    /// WiFi → WWAN coalesces: the old WiFi loop is cancelled and only the WWAN interval (30 s)
    /// is observed going forward. No two loops race with different intervals.
    func testRestartCoalescesOldLoop() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        // Start on WiFi.
        await queue.networkConnectivityChanged(.reachableViaWiFi)
        XCTAssertTrue(gated.waitForRequested(atLeast: 1), "WiFi loop must park on its first sleep")
        XCTAssertEqual(gated.requested.first, FlushConstants.wifiFlushInterval)

        // Switch to WWAN while the WiFi loop is parked. start() inside the handler cancels the
        // old loop and starts a new one — only the cellular interval should appear after this.
        await queue.networkConnectivityChanged(.reachableViaWWAN)

        // The WWAN loop should now be running and park on a 30-second sleep.
        XCTAssertTrue(gated.waitForRequested(atLeast: 2), "WWAN loop must request a sleep")
        XCTAssertEqual(gated.requested[1], FlushConstants.cellularFlushInterval,
                       "after WiFi→WWAN the new loop must sleep the cellular interval")

        // Confirm we never see a WiFi-interval sleep from the replaced loop racing in.
        gated.releaseOneTick()
        XCTAssertTrue(gated.waitForRequested(atLeast: 3), "loop re-parks after second tick")
        XCTAssertEqual(gated.requested[2], FlushConstants.cellularFlushInterval,
                       "only the cellular interval must be observed after coalescing")

        await queue.stop()
    }

    // MARK: - Invalid-field clear

    /// A 422 with `/data/attributes/email` pointer must nil `IdentityStore.current.email` and
    /// dequeue the request (not restore/resend). Parity: `resetStateAndDequeue` in the reducer.
    /// Seeds externalId + email to verify the read-modify-write clears ONLY the targeted field.
    func testInvalidEmailClearsCanonicalEmailAndDequeues() async {
        QueueStore.register(makeQueueStore())

        // Seed email AND externalId so we can verify only email is cleared.
        var identity = IdentityStore.shared.current
        identity.email = "invalid@example.com"
        identity.externalId = "ext-id-123"
        IdentityStore.shared.update(identity)
        let seededAnonymousId = IdentityStore.shared.current.anonymousId

        let errorData = makeInvalidFieldErrorData(pointer: "/data/attributes/email")
        let spy = SendSpy(results: [
            .failure(.httpError(422, errorData))
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "bad-email"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        let afterIdentity = IdentityStore.shared.current
        XCTAssertNil(afterIdentity.email,
                     "email must be cleared on the canonical IdentityStore after a 422 invalid-email")
        XCTAssertEqual(afterIdentity.externalId, "ext-id-123",
                       "externalId must survive the email-field clear (only targeted field is nil'd)")
        XCTAssertEqual(afterIdentity.anonymousId, seededAnonymousId,
                       "anonymousId must survive the email-field clear")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty,
                      "request must be dequeued (not restored) after clearing invalid email")
        XCTAssertEqual(spy.sentIds, ["bad-email"], "request sent exactly once")
    }

    /// A 422 with `/data/attributes/phone_number` pointer must nil
    /// `IdentityStore.current.phoneNumber` and dequeue the request.
    /// Seeds externalId + phoneNumber to verify the read-modify-write clears ONLY the targeted field.
    func testInvalidPhoneClearsCanonicalPhoneAndDequeues() async {
        QueueStore.register(makeQueueStore())

        // Seed phoneNumber AND externalId so we can verify only phoneNumber is cleared.
        var identity = IdentityStore.shared.current
        identity.phoneNumber = "+15005550000"
        identity.externalId = "ext-id-456"
        IdentityStore.shared.update(identity)
        let seededAnonymousId = IdentityStore.shared.current.anonymousId

        let errorData = makeInvalidFieldErrorData(pointer: "/data/attributes/phone_number")
        let spy = SendSpy(results: [
            .failure(.httpError(422, errorData))
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "bad-phone"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        let afterIdentity = IdentityStore.shared.current
        XCTAssertNil(afterIdentity.phoneNumber,
                     "phone must be cleared on the canonical IdentityStore after a 422 invalid-phone")
        XCTAssertEqual(afterIdentity.externalId, "ext-id-456",
                       "externalId must survive the phone-field clear (only targeted field is nil'd)")
        XCTAssertEqual(afterIdentity.anonymousId, seededAnonymousId,
                       "anonymousId must survive the phone-field clear")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty,
                      "request must be dequeued (not restored) after clearing invalid phone")
        XCTAssertEqual(spy.sentIds, ["bad-phone"], "request sent exactly once")
    }
}
