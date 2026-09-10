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

    // MARK: - Test doubles

    /// A `send` stub that always succeeds. The run-loop tests drive an empty queue, so `flush()`
    /// never actually calls it, but the actor still requires one.
    private var alwaysSucceeds: RequestQueue.Send {
        { _, _ in .success(Data()) }
    }

    /// A clock that records each requested sleep duration and then suspends the run loop until the
    /// test consumes one tick. This makes the loop advance one controlled step at a time so the
    /// stub `flush()` cannot busy-spin thousands of ticks between assertions.
    private final class GatedSleepClock: @unchecked Sendable {
        private let lock = NSLock()
        private var _requested: [TimeInterval] = []
        // The loop parks on this continuation each tick; the test resumes it to release one step.
        private var _waiter: CheckedContinuation<Void, Never>?

        var requested: [TimeInterval] {
            lock.lock(); defer { lock.unlock() }
            return _requested
        }

        var clock: SleepClock {
            SleepClock { [self] seconds in
                // Resume the parked continuation on cancellation too, so a `stop()` that cancels the
                // loop mid-sleep never leaks it (which would trip CheckedContinuation's misuse trap).
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        lock.lock()
                        _requested.append(seconds)
                        // If cancellation already fired, resume immediately rather than parking a
                        // continuation nobody will ever release.
                        if Task.isCancelled {
                            lock.unlock()
                            continuation.resume()
                        } else {
                            _waiter = continuation
                            lock.unlock()
                        }
                    }
                } onCancel: {
                    resumeWaiter()
                }
            }
        }

        /// Releases exactly one parked sleep, letting the loop run one `flush()` and re-park.
        func releaseOneTick() { resumeWaiter() }

        private func resumeWaiter() {
            lock.lock()
            let waiter = _waiter
            _waiter = nil
            lock.unlock()
            waiter?.resume()
        }

        /// Blocks (bounded) until at least `count` sleeps have been requested.
        func waitForRequested(atLeast count: Int, timeout: TimeInterval = 2.0) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if requested.count >= count { return true }
                Thread.sleep(forTimeInterval: 0.01)
            }
            return requested.count >= count
        }
    }

    /// Records every write so `stop()`'s lease-restore behavior is observable via the shared store:
    /// a `prepend` under the hood calls `save`, so a non-empty `savedBatches` after `stop()` proves a
    /// restore happened (and its absence proves it did not).
    private final class WriteSpyDiskIO {
        private let lock = NSLock()
        private var _stored: [KlaviyoRequest] = []
        private var _savedBatches: [[KlaviyoRequest]] = []

        var stored: [KlaviyoRequest] { lock.lock(); defer { lock.unlock() }; return _stored }
        var savedBatches: [[KlaviyoRequest]] {
            lock.lock(); defer { lock.unlock() }; return _savedBatches
        }

        func makeIO() -> QueueStore.DiskIO {
            QueueStore.DiskIO(
                load: { [weak self] in self?.stored ?? [] },
                save: { [weak self] requests in
                    guard let self else { return }
                    self.lock.lock(); defer { self.lock.unlock() }
                    self._stored = requests
                    self._savedBatches.append(requests)
                }
            )
        }
    }

    private func makeStore(diskIO: WriteSpyDiskIO = WriteSpyDiskIO()) -> QueueStore {
        QueueStore(
            diskIO: diskIO.makeIO(),
            scheduler: QueueStore.PersistScheduler { _, work in work() },
            emitWarning: { _ in }
        )
    }

    /// Records the id of every request handed to `send`, in call order, so FIFO ordering and
    /// call-count assertions are observable. Defaults to always-success.
    private final class SendSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _sentIds: [String] = []

        var sentIds: [String] { lock.lock(); defer { lock.unlock() }; return _sentIds }

        var send: RequestQueue.Send {
            { [self] request, _ in
                lock.lock()
                _sentIds.append(request.id)
                lock.unlock()
                return .success(Data())
            }
        }
    }

    /// A `send` stub whose FIRST invocation parks on a continuation until the test releases it, so a
    /// flush can be held mid-send (with a batch leased in `requestsInFlight`) while a concurrent
    /// flush is driven against the actor. Subsequent invocations succeed immediately. `started`
    /// fulfills once the first send has parked, giving the test a bounded signal to synchronize on.
    private final class ParkingSendSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _sentIds: [String] = []
        private var _resume: CheckedContinuation<Void, Never>?
        private var _parked = false
        let started: XCTestExpectation

        init(started: XCTestExpectation) {
            self.started = started
        }

        var sentIds: [String] { lock.lock(); defer { lock.unlock() }; return _sentIds }

        var send: RequestQueue.Send {
            { [self] request, _ in
                let shouldPark: Bool = {
                    lock.lock(); defer { lock.unlock() }
                    _sentIds.append(request.id)
                    let firstCall = !_parked
                    _parked = true
                    return firstCall
                }()
                if shouldPark {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        lock.lock()
                        _resume = continuation
                        lock.unlock()
                        started.fulfill()
                    }
                }
                return .success(Data())
            }
        }

        /// Releases the parked first send so flush A can finish draining its batch.
        func release() {
            lock.lock()
            let continuation = _resume
            _resume = nil
            lock.unlock()
            continuation?.resume()
        }
    }

    /// A `send` stub driven by a scripted queue of results, consumed in order (the last result
    /// repeats once the script is exhausted). Records the id of every request sent so retry/dequeue
    /// behavior is observable. Thread-safe for use from the actor under test.
    private final class ScriptedSendSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _results: [Result<Data, KlaviyoAPIError>]
        private var _sentIds: [String] = []
        private var _sentAttempts: [Int] = []

        init(results: [Result<Data, KlaviyoAPIError>]) {
            _results = results
        }

        var sentIds: [String] { lock.lock(); defer { lock.unlock() }; return _sentIds }
        var sentAttempts: [Int] { lock.lock(); defer { lock.unlock() }; return _sentAttempts }

        var send: RequestQueue.Send {
            { [self] request, info in
                lock.lock()
                _sentIds.append(request.id)
                _sentAttempts.append(info.attemptNumber)
                let result = _results.count > 1
                    ? _results.removeFirst()
                    : (_results.first ?? .success(Data()))
                lock.unlock()
                return result
            }
        }
    }

    /// Builds a `.registerPushToken` request whose payload carries the given token/enablement/
    /// background, matching the fields `flush()` writes back to `IdentityStore` on success.
    private func makeRegisterPushTokenRequest(
        id: String = UUID().uuidString,
        token: String,
        enablement: PushEnablement = .authorized,
        background: PushBackground = .available
    ) -> KlaviyoRequest {
        let payload = PushTokenPayload(
            pushToken: token,
            enablement: enablement.rawValue,
            background: background.rawValue,
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        return KlaviyoRequest(id: id, endpoint: .registerPushToken("test-api-key", payload))
    }

    private func makeCreateProfileRequest(id: String = UUID().uuidString) -> KlaviyoRequest {
        KlaviyoRequest(
            id: id,
            endpoint: .createProfile("test-api-key", CreateProfilePayload(data: .test))
        )
    }

    /// A request whose endpoint has `maxRetries == 1`, so a single retry increment (count → 2)
    /// exceeds the limit — letting the maxRetries-drop path be exercised in one flush.
    private func makeLowRetryRequest(id: String = UUID().uuidString) -> KlaviyoRequest {
        KlaviyoRequest(
            id: id,
            endpoint: .resolveDestinationURL(
                trackingLink: URL(string: "https://klaviyo.com")!,
                profileInfo: ProfilePayload(anonymousId: "anon-1")
            )
        )
    }

    // MARK: - flush()

    /// `willDrain` runs before the drain, so a request it enqueues is part of the leased batch and
    /// gets sent in this same flush.
    func testWillDrainRunsBeforeDrain() async {
        QueueStore.register(makeStore())
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
        QueueStore.register(makeStore())
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
        QueueStore.register(makeStore())
        let spy = SendSpy()
        let queue = RequestQueue(clock: .immediate, send: spy.send)

        await queue.flushNow()

        XCTAssertTrue(spy.sentIds.isEmpty, "send must not be called for an empty queue")
    }

    /// On a successful `.registerPushToken`, the payload's token (and enablement/background) is
    /// written back to the canonical `IdentityStore`.
    func testRegisterSuccessWritesTokenBackToIdentityStore() async {
        QueueStore.register(makeStore())
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
        QueueStore.register(makeStore())
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
        QueueStore.register(makeStore())
        let gated = GatedSleepClock()
        let queue = RequestQueue(clock: gated.clock, send: alwaysSucceeds)

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
        QueueStore.register(makeStore())
        let gated = GatedSleepClock()
        let queue = RequestQueue(clock: gated.clock, send: alwaysSucceeds)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        await queue.stop() // must return promptly
    }

    /// A `start()` after a `stop()` works — the loop can be restarted.
    func testRestartAfterStop() async {
        QueueStore.register(makeStore())
        let gated = GatedSleepClock()
        let queue = RequestQueue(clock: gated.clock, send: alwaysSucceeds)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        await queue.stop()

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 2), "a fresh loop should request another sleep")
        await queue.stop()
    }

    /// With an empty in-flight lease, `stop()` must not prepend anything to the shared store.
    func testStopWithEmptyLeaseDoesNotPrepend() async {
        let spy = WriteSpyDiskIO()
        QueueStore.register(makeStore(diskIO: spy))
        let gated = GatedSleepClock()
        let queue = RequestQueue(clock: gated.clock, send: alwaysSucceeds)

        await queue.start()
        XCTAssertTrue(gated.waitForRequested(atLeast: 1))
        await queue.stop()

        XCTAssertTrue(spy.savedBatches.isEmpty, "empty lease must not restore anything")
        XCTAssertTrue(spy.stored.isEmpty, "no requests should have been written")
    }

    /// `flushNow()` returns without hanging against an empty queue.
    func testFlushNowReturns() async {
        QueueStore.register(makeStore())
        let gated = GatedSleepClock()
        let queue = RequestQueue(clock: gated.clock, send: alwaysSucceeds)
        await queue.flushNow()
    }

    // MARK: - Re-entrancy

    /// A second flush must not clobber an in-flight lease held by a suspended flush. Flush A parks
    /// mid-`send` with its whole batch leased; while it is parked, flush B runs against the now-empty
    /// store and must no-op (guarded by `isFlushing`) WITHOUT draining or dropping anything. When A
    /// resumes it finishes its batch, so every originally-queued request is sent exactly once and the
    /// store is left empty — nothing stranded, nothing lost.
    func testConcurrentFlushDoesNotClobberInFlightLease() async {
        QueueStore.register(makeStore())
        let started = expectation(description: "flush A parked mid-send")
        let spy = ParkingSendSpy(started: started)
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
        QueueStore.register(makeStore())
        let spy = ScriptedSendSpy(results: [
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
        QueueStore.register(makeStore())
        let recording = RecordingSleepClock()
        let spy = ScriptedSendSpy(results: [
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
        QueueStore.register(makeStore())
        let recording = RecordingSleepClock()
        let spy = ScriptedSendSpy(results: [
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
        QueueStore.register(makeStore())
        let spy = ScriptedSendSpy(results: [
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
        QueueStore.register(makeStore(diskIO: diskSpy))
        let spy = ScriptedSendSpy(results: [
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
        QueueStore.register(makeStore())
        let recording = RecordingSleepClock()
        let spy = ScriptedSendSpy(results: [
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
        QueueStore.register(makeStore())
        let spy = ScriptedSendSpy(results: [
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

    // MARK: - Invalid-field clear

    /// Builds a 422 error-response JSON body with the given source pointer, matching the Klaviyo
    /// API error envelope format that `classifyFailure` → `parseError` decodes.
    private func makeInvalidFieldErrorData(pointer: String) -> Data {
        """
        {
            "errors": [{
                "id": "err-1",
                "status": 422,
                "code": "invalid",
                "title": "Invalid input.",
                "detail": "Invalid value.",
                "source": { "pointer": "\(pointer)" }
            }]
        }
        """.data(using: .utf8)!
    }

    /// A 422 with `/data/attributes/email` pointer must nil `IdentityStore.current.email` and
    /// dequeue the request (not restore/resend). Parity: `resetStateAndDequeue` in the reducer.
    /// Seeds externalId + email to verify the read-modify-write clears ONLY the targeted field.
    func testInvalidEmailClearsCanonicalEmailAndDequeues() async {
        QueueStore.register(makeStore())

        // Seed email AND externalId so we can verify only email is cleared.
        var identity = IdentityStore.shared.current
        identity.email = "invalid@example.com"
        identity.externalId = "ext-id-123"
        IdentityStore.shared.update(identity)
        let seededAnonymousId = IdentityStore.shared.current.anonymousId

        let errorData = makeInvalidFieldErrorData(pointer: "/data/attributes/email")
        let spy = ScriptedSendSpy(results: [
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
        QueueStore.register(makeStore())

        // Seed phoneNumber AND externalId so we can verify only phoneNumber is cleared.
        var identity = IdentityStore.shared.current
        identity.phoneNumber = "+15005550000"
        identity.externalId = "ext-id-456"
        IdentityStore.shared.update(identity)
        let seededAnonymousId = IdentityStore.shared.current.anonymousId

        let errorData = makeInvalidFieldErrorData(pointer: "/data/attributes/phone_number")
        let spy = ScriptedSendSpy(results: [
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
