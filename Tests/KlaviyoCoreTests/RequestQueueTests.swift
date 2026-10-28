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
    private var wallClock: TestClock!

    override func setUp() {
        super.setUp()
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        fileIO = FileIODouble()
        // Settable wall clock (shared `TestClock`) so `nextAttemptAt` gating is driven by time.
        wallClock = TestClock(Date(timeIntervalSince1970: 1_234_567_890))
        environment = fileIO.makeEnvironment()
        let wallClock = wallClock!
        environment.date = { wallClock.now() }
        // An apiKey is required for `flush()` to run (pre-init flushing stays gated).
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "test-api-key"))
    }

    override func tearDown() {
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        fileIO = nil
        wallClock = nil
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

    /// The success write-through is guarded on a token match (symmetric with the failure-path
    /// rollback): if a newer token was set (e.g. a later `setPushToken`) after an older register was
    /// enqueued, that older register completing successfully must NOT revert the canonical token to
    /// the stale value.
    func testRegisterSuccessPreservesNewerToken() async {
        QueueStore.register(makeQueueStore())
        let oldPayload = PushTokenPayload(
            pushToken: "tok-old",
            enablement: PushEnablement.authorized.rawValue,
            background: PushBackground.available.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        let newerToken = PushTokenData(PushTokenPayload(
            pushToken: "tok-new",
            enablement: PushEnablement.authorized.rawValue,
            background: PushBackground.available.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        ))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-1"))
        IdentityStore.shared.updatePushToken(newerToken)
        let spy = SendSpy(results: [.success(Data())])
        QueueStore.shared.enqueue(
            KlaviyoRequest(id: "reg", endpoint: .registerPushToken("test-api-key", oldPayload)),
            persist: .synchronous
        )
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(IdentityStore.shared.pushToken, newerToken,
                       "a newer token set after the older register must survive that register succeeding")
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

    /// `stop()` while the loop is parked in the interval sleep must NOT run a trailing `flush()`.
    /// Regression: the loop previously swallowed the sleep's cancellation with `try?` and flushed
    /// once more, so `stop()` on the idle wait would still drain+send (harmful on backgrounding,
    /// where the interval is still finite).
    func testStopDuringIdleSleepDoesNotFlush() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy()
        // `willDrain` fires at the very top of `flush()`; an inverted expectation asserts flush
        // never runs after the cancel.
        let didFlush = expectation(description: "flush ran after stop()")
        didFlush.isInverted = true
        let queue = RequestQueue(clock: gated.clock, send: spy.send, willDrain: { didFlush.fulfill() })

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1), "loop should park in the interval sleep")
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "idle"), persist: .synchronous)

        await queue.stop() // cancels the loop parked in the sleep

        await fulfillment(of: [didFlush], timeout: 0.5)
        XCTAssertEqual(spy.sentIds, [], "no request should be sent by a cancelled idle loop")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["idle"],
                       "the queued request must remain durable, not drained by a trailing flush")
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

    /// A transient network error stops the flush and restores the head to the queue (not dropped),
    /// with its own attempt count advanced. Once its floored backoff (10s) elapses it resends as attempt 2.
    func testNetworkErrorRetriesAfterOwnBackoffAndIncrementsCount() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [networkFailure, .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "net-retry"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["net-retry"])
        XCTAssertEqual(QueueStore.shared.entries.map(\.attempts), [1],
                       "network error restores the request with its own attempt counted")

        wallClock.advance(by: FlushConstants.wifiFlushInterval)
        await queue.flushNow()
        XCTAssertEqual(spy.sentAttempts, [1, 2], "attempt number advances on the resend")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "request dequeued after success")
    }

    /// `nextAttemptAt` gates the resend on wall-clock time, not on how many flushes run: any number
    /// of flushes before the deadline is a no-op, and the first flush at/after it resends.
    func testNextAttemptAtGatesFlushUntilDeadline() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 25)), .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "rate"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)
        let failedAt = wallClock.now()

        await queue.flushNow()
        XCTAssertEqual(QueueStore.shared.entries.first?.nextAttemptAt, failedAt.addingTimeInterval(25),
                       "deadline is an absolute wall-clock time: failure time + backoff")

        for _ in 0..<5 {
            await queue.flushNow()
        }
        wallClock.advance(by: 24)
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["rate"], "no resend before the deadline, however many flushes run")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["rate"],
                       "request stays durable in the queue while it waits")

        wallClock.advance(by: 1)
        await queue.flushNow()
        XCTAssertEqual(spy.sentAttempts, [1, 2], "resent at the deadline with its attempt advanced")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "request dequeued after successful resend")
    }

    /// A server error backs off like a rate-limit: gated on its own deadline, then resent.
    func testServerErrorBacksOffThenResends() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.serverError(statusCode: 503, backOff: 5)), .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "srv"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["srv"], "not resent inside the backoff window")

        wallClock.advance(by: 10)
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["srv", "srv"], "resent once the backoff elapsed")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "request dequeued after successful resend")
    }

    // MARK: - Transport error backoff

    /// Successive transport errors (2, 4, 8s, floored to 10s here) are each gated on the request's own
    /// deadline, and its attempt keeps climbing. Escalation past the floor is in the scheduling tests.
    func testSuccessiveNetworkErrorsEscalateOwnBackoff() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [networkFailure, networkFailure, networkFailure, .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "net-escalate"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        for sent in 1...3 {
            wallClock.advance(by: FlushConstants.wifiFlushInterval - 1)
            await queue.flushNow()
            XCTAssertEqual(spy.sentIds.count, sent, "still gated 1s before the floored deadline")
            wallClock.advance(by: 1)
            await queue.flushNow()
        }
        XCTAssertEqual(spy.sentAttempts, [1, 2, 3, 4],
                       "attempt number climbs across transport failures, never pins at 1")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "dequeued after the successful resend")
    }

    /// A rate-limited request that then hits a transport error keeps escalating on its own count:
    /// attempt 2 fails and backs off (floored to 10s), not a reset to attempt 1.
    func testRateLimitBackoffSurvivesASubsequentNetworkError() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 25)), networkFailure, .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "429-then-net"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        wallClock.advance(by: 25)
        await queue.flushNow()
        XCTAssertEqual(spy.sentAttempts, [1, 2])
        XCTAssertEqual(QueueStore.shared.entries.map(\.attempts), [2],
                       "the transport failure after a 429 restores the request, not drops it")

        wallClock.advance(by: 9)
        await queue.flushNow()
        XCTAssertEqual(spy.sentAttempts, [1, 2], "floored 10s backoff still pending after 9s")
        wallClock.advance(by: 1)
        await queue.flushNow()
        XCTAssertEqual(spy.sentAttempts, [1, 2, 3], "attempt escalates again, not reset to 1")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "dequeued after the successful resend")
    }

    /// An offline `.infinity` flush interval cannot poison the backoff path: `flush()`'s
    /// `flushInterval.isFinite` guard short-circuits before any deadline check. The request stays
    /// durable while offline and is resent once reachable again.
    func testNetworkErrorWhileOfflineDoesNotProduceInfiniteBackoffAndResendsOnceReachable() async {
        QueueStore.register(makeQueueStore())
        let gated = GatedSleepClock()
        let spy = SendSpy(results: [networkFailure, .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "offline-net"), persist: .synchronous)
        let queue = RequestQueue(clock: gated.clock, send: spy.send)

        await queue.flushNow()
        await queue.networkConnectivityChanged(.notReachable)
        wallClock.advance(by: FlushConstants.wifiFlushInterval)
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["offline-net"], "flush must no-op while offline; no resend attempted")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["offline-net"],
                       "request remains durable and untouched while offline")

        await queue.networkConnectivityChanged(.reachableViaWiFi)
        await queue.stop()
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["offline-net", "offline-net"], "resent once reconnected")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "dequeued on successful resend after reconnect")
    }

    /// A request whose own attempts reach its endpoint's `maxRetries` is dropped, not restored. The
    /// low-retry endpoint (`maxRetries == 1`) exhausts on its first failure.
    func testExceedingMaxRetriesDropsRequest() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [networkFailure])
        QueueStore.shared.enqueue(makeLowRetryRequest(id: "doomed"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["doomed"], "sent once")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty,
                      "request exceeding maxRetries must be dropped, not restored")
    }

    /// The 50-attempt cap is spent by one request alone: exactly 50 sends, then it's dropped.
    func testRequestIsDroppedAfterExactlyMaxRetriesOwnAttempts() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.serverError(statusCode: 503, backOff: 1))])
        let request = makeCreateProfileRequest(id: "capped")
        QueueStore.shared.enqueue(request, persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        for _ in 0..<(request.endpoint.maxRetries + 5) {
            await queue.flushNow()
            wallClock.advance(by: FlushConstants.wifiFlushInterval)
        }

        XCTAssertEqual(spy.sentAttempts, Array(1...request.endpoint.maxRetries),
                       "header attempt count runs 1...maxRetries, then the request is dropped")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty)
    }

    /// On a retryable failure of the head, the remaining leased requests are restored to the queue
    /// (via `.synchronous` prepend) and the in-memory lease is cleared.
    func testFailureRestoresRemainingLeaseToQueue() async {
        let diskSpy = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: diskSpy))
        let spy = SendSpy(results: [networkFailure])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "head"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "tail"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["head"], "flush stops at the failing head")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["head", "tail"],
                       "the whole remaining lease is restored to the front of the queue")
        XCTAssertEqual(QueueStore.shared.entries.map(\.attempts), [1, 0],
                       "only the failing head carries a retry; the tail's state is untouched")
        XCTAssertFalse(diskSpy.savedBatches.isEmpty, "restore must persist synchronously")
    }

    /// A backoff-path failure that exhausts a low-retry request drops it, and a later request still
    /// sends at attempt 1: there is no queue-wide counter left over to stall or inherit.
    func testExceedingMaxRetriesOnBackoffDropsRequest() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 5)), .success(Data())])
        QueueStore.shared.enqueue(makeLowRetryRequest(id: "backoff-doomed"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        XCTAssertTrue(QueueStore.shared.requests.isEmpty,
                      "head must be dropped (not restored) when it exhausts maxRetries")

        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "after"), persist: .synchronous)
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["backoff-doomed", "after"],
                       "a request enqueued after the drop sends immediately, no inherited backoff")
        XCTAssertEqual(spy.sentAttempts.last, 1, "the successor sends at attempt 1")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "successor dequeued after success")
    }

    // MARK: - Per-request retry state

    /// The regression this model exists for: A fails and backs off; priority request B is
    /// front-inserted during A's backoff. B must send at once at attempt 1, and A must keep its own
    /// count and deadline rather than B inheriting them.
    func testPriorityInsertDuringBackoffDoesNotInheritRetryState() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 60)), .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "A"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        let aDeadline = QueueStore.shared.entries.first?.nextAttemptAt

        QueueStore.shared.enqueue(makePriorityEventRequest(id: "B"), persist: .synchronous)
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["B", "A"], "B front-inserted ahead of A")
        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["A", "B"], "B sends immediately, not gated by A's backoff")
        XCTAssertEqual(spy.sentAttempts, [1, 1],
                       "X-Klaviyo-Attempt-Count for B reflects B's own count, not A's")
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["A"], "A remains queued behind")
        XCTAssertEqual(QueueStore.shared.entries.first?.attempts, 1, "A keeps its own attempt count")
        XCTAssertEqual(QueueStore.shared.entries.first?.nextAttemptAt, aDeadline,
                       "A keeps its own deadline")
    }

    /// Mixed queue: a backing-off head holds the serial queue (Android `PendingRetry` parity), but a
    /// priority request jumping ahead sends while the other is still backing off, and the
    /// backing-off request resumes on its own schedule afterwards.
    func testMixedQueueSendsOthersWhileOneBacksOff() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [
            .failure(.serverError(statusCode: 503, backOff: 30)),
            .success(Data()),
            .success(Data()),
            .success(Data())
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "slow"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "tail"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        QueueStore.shared.enqueue(makePriorityEventRequest(id: "urgent"), persist: .synchronous)
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["slow", "urgent"],
                       "urgent sends while slow backs off; tail waits behind slow (serial FIFO)")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["slow", "tail"])

        wallClock.advance(by: 30)
        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["slow", "urgent", "slow", "tail"],
                       "slow resumes on its own deadline, then the rest drains")
        XCTAssertEqual(spy.sentAttempts, [1, 1, 2, 1], "each request reports its own attempt number")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty)
    }

    /// Exhausting A's cap drops A only; B (queued behind A) stays queued with a clean state and
    /// sends next.
    func testExhaustingOneRequestsCapLeavesOthersSendable() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 5)), .success(Data())])
        QueueStore.shared.enqueue(makeLowRetryRequest(id: "A"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "B"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        XCTAssertEqual(QueueStore.shared.entries.map(\.id), ["B"], "only A is dropped")
        XCTAssertEqual(QueueStore.shared.entries.first?.attempts, 0, "B's own state is untouched")
        XCTAssertNil(QueueStore.shared.entries.first?.nextAttemptAt)

        await queue.flushNow()
        XCTAssertEqual(spy.sentIds, ["A", "B"])
        XCTAssertEqual(spy.sentAttempts, [1, 1])
        XCTAssertTrue(QueueStore.shared.requests.isEmpty)
    }

    /// A clock set back past the failure time must not strand the request behind a deadline that is
    /// now far in the future; the backoff is released and it resends.
    func testClockRollbackReleasesBackoff() async {
        QueueStore.register(makeQueueStore())
        let spy = SendSpy(results: [.failure(.rateLimitError(backOff: 300)), .success(Data())])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "rolled"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()
        wallClock.advance(by: -86_400)
        await queue.flushNow()

        XCTAssertEqual(spy.sentIds, ["rolled", "rolled"], "rollback releases the stale deadline")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty)
    }

    /// App relaunch mid-backoff: retry state is in-memory only, so a fresh store over the same disk
    /// restores the request at attempts 0 / no deadline and it sends at attempt 1 straight away
    /// (Android parity: attempts and status reset on restart).
    func testRelaunchDuringBackoffResetsRetryState() async {
        let diskSpy = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: diskSpy))
        let failing = SendSpy(results: [.failure(.rateLimitError(backOff: 120))])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "persisted"), persist: .synchronous)
        await RequestQueue(clock: .immediate, send: failing.send).flushNow()
        XCTAssertNotNil(QueueStore.shared.entries.first?.nextAttemptAt, "backing off before relaunch")

        // Relaunch: new store hydrating from the same disk, new engine.
        QueueStore.register(makeQueueStore(diskIO: diskSpy))
        XCTAssertEqual(QueueStore.shared.entries.map(\.attempts), [0])
        XCTAssertNil(QueueStore.shared.entries.first?.nextAttemptAt)

        let spy = SendSpy()
        await RequestQueue(clock: .immediate, send: spy.send).flushNow()
        XCTAssertEqual(spy.sentIds, ["persisted"], "sends immediately after relaunch")
        XCTAssertEqual(spy.sentAttempts, [1], "attempt count restarts at 1")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty)
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

    // MARK: - Optimistic push-token reconciliation

    /// When a `registerPushToken` is permanently dropped (here a non-retryable `.internalError`), the
    /// optimistic `IdentityStore` token written when the caller set it is rolled back — so a later
    /// identical `setPushToken` re-enqueues instead of dedup-skipping a token that never registered.
    func testRegisterPermanentFailureClearsMatchingOptimisticToken() async {
        QueueStore.register(makeQueueStore())
        let payload = PushTokenPayload(
            pushToken: "tok-1",
            enablement: PushEnablement.authorized.rawValue,
            background: PushBackground.available.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-1"))
        IdentityStore.shared.updatePushToken(PushTokenData(payload))
        let spy = SendSpy(results: [.failure(.internalError("boom"))])
        QueueStore.shared.enqueue(
            KlaviyoRequest(id: "reg", endpoint: .registerPushToken("test-api-key", payload)),
            persist: .synchronous
        )
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "permanently failed register is dropped")
        XCTAssertNil(IdentityStore.shared.pushToken,
                     "optimistic token must be cleared when its register is permanently dropped")
    }

    /// The rollback is guarded on a token match: if a newer token was set after the failing register
    /// was enqueued, dropping the old register must not wipe the newer token.
    func testRegisterPermanentFailurePreservesNewerToken() async {
        QueueStore.register(makeQueueStore())
        let oldPayload = PushTokenPayload(
            pushToken: "tok-old",
            enablement: PushEnablement.authorized.rawValue,
            background: PushBackground.available.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        let newerToken = PushTokenData(PushTokenPayload(
            pushToken: "tok-new",
            enablement: PushEnablement.authorized.rawValue,
            background: PushBackground.available.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        ))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-1"))
        IdentityStore.shared.updatePushToken(newerToken)
        let spy = SendSpy(results: [.failure(.internalError("boom"))])
        QueueStore.shared.enqueue(
            KlaviyoRequest(id: "reg", endpoint: .registerPushToken("test-api-key", oldPayload)),
            persist: .synchronous
        )
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(IdentityStore.shared.pushToken, newerToken,
                       "a newer token set after the failing register must be preserved")
    }

    /// Android parity: a server 4xx rejection of a register does NOT clear the token (unlike a
    /// non-retryable internal failure), so we don't churn the same token back onto the queue.
    func testRegisterHttpErrorKeepsToken() async {
        QueueStore.register(makeQueueStore())
        let payload = PushTokenPayload(
            pushToken: "tok-1",
            enablement: PushEnablement.authorized.rawValue,
            background: PushBackground.available.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        let tokenData = PushTokenData(payload)
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-1"))
        IdentityStore.shared.updatePushToken(tokenData)
        let spy = SendSpy(results: [.failure(.httpError(400, Data()))])
        QueueStore.shared.enqueue(
            KlaviyoRequest(id: "reg", endpoint: .registerPushToken("test-api-key", payload)),
            persist: .synchronous
        )
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertEqual(IdentityStore.shared.pushToken, tokenData,
                       "a 4xx rejection must not clear the token (Android parity)")
    }

    /// The realistic permanent-failure path: a register that exhausts its retry ceiling on repeated
    /// network errors is dropped, and its optimistic token is rolled back like the non-retryable case.
    func testRegisterExhaustingRetriesClearsOptimisticToken() async {
        QueueStore.register(makeQueueStore())
        let payload = PushTokenPayload(
            pushToken: "tok-1",
            enablement: PushEnablement.authorized.rawValue,
            background: PushBackground.available.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-1"))
        IdentityStore.shared.updatePushToken(PushTokenData(payload))
        let spy = SendSpy(results: [.failure(.networkError(NSError(domain: "test", code: -1)))])
        QueueStore.shared.enqueue(
            KlaviyoRequest(id: "reg", endpoint: .registerPushToken("test-api-key", payload)),
            persist: .synchronous
        )
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        // Each network error backs off on this request's own deadline; step the wall clock past the
        // 300s cap each flush so the 50 attempts run back to back.
        var ticks = 0
        let tickBudget = 200
        while !QueueStore.shared.requests.isEmpty, ticks < tickBudget {
            await queue.flushNow()
            wallClock.advance(by: TimeInterval(RetryBackoffConstants.maxBackoffSeconds))
            ticks += 1
        }
        XCTAssertEqual(spy.sentAttempts.count, 50, "dropped after exactly its own 50 attempts")

        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "register must be dropped after exhausting retries")
        XCTAssertNil(IdentityStore.shared.pushToken,
                     "optimistic token must be cleared once the register exhausts its retries")
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

    /// `.notReachable` restores any in-flight lease to `QueueStore`.
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

    /// Durability during a backoff is inherent: after a rate-limit failure the request is restored to
    /// `QueueStore` (on disk) and only its retry bookkeeping lives in memory. There is no backoff
    /// sleep to be interrupted, so a `stop()` mid-wait is trivially safe — the request is already
    /// durable in the store, so nothing can be stranded in memory across shutdown.
    func testBackoffKeepsRequestDurableInQueueStore() async {
        let diskSpy = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: diskSpy))
        let spy = SendSpy(results: [
            .failure(.rateLimitError(backOff: 60))
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "durable"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        // Rate-limit failure: the request must be restored to the durable store synchronously.
        await queue.flushNow()

        XCTAssertFalse(diskSpy.savedBatches.isEmpty,
                       "the rate-limited request must be restored to QueueStore synchronously")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["durable"],
                       "request stays durable in the store during the backoff wait, not held in memory")
        XCTAssertEqual(spy.sentIds, ["durable"], "sent once; the backoff is a deadline, not a sleep")

        // A `stop()` mid-wait is trivially safe: the request is already on disk, in-flight is empty.
        await queue.stop()
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["durable"],
                       "stop() during the backoff wait leaves the durable request untouched")
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
    /// dequeue the request (not restore/resend).
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
