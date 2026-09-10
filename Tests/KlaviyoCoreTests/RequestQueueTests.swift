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
}
