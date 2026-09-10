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
        QueueStore.resetShared()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
    }

    override func tearDown() {
        SDKConfigStore.shared.reset()
        QueueStore.resetShared()
        fileIO = nil
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

    // MARK: - Test doubles

    /// A `send` stub that always succeeds. The stub `flush()` in this task never calls it, but the
    /// actor still requires one.
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
    /// (The non-empty lease-restore path can't be exercised until `flush()` populates
    /// `requestsInFlight` in Task 4 — deferred.)
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

    /// `flushNow()` returns without hanging (the stub flush is a no-op in this task).
    func testFlushNowReturns() async {
        QueueStore.register(makeStore())
        let gated = GatedSleepClock()
        let queue = RequestQueue(clock: gated.clock, send: alwaysSucceeds)
        await queue.flushNow()
    }
}
