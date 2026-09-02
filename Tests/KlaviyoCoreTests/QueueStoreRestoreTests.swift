//
//  QueueStoreRestoreTests.swift
//  klaviyo-swift-sdk
//
//  Split from QueueStoreTests.swift, matching the existing QueueStoreRegistryTests.swift split.
//

@testable import KlaviyoCore
import XCTest

final class QueueStoreRestoreTests: XCTestCase {
    private func request(_ id: String, priority: RequestPriority = .standard,
                         at date: Date = Date(timeIntervalSince1970: 0)) -> KlaviyoRequest {
        KlaviyoRequest(
            id: id,
            endpoint: .createProfile("foo", CreateProfilePayload(data: .test)),
            enqueuedAt: date,
            priority: priority
        )
    }

    /// Thread-safe in-memory DiskIO that counts loads/saves for assertions.
    private final class SpyDiskIO {
        private let lock = NSLock()
        private var _stored: [KlaviyoRequest]
        private var _saveCount = 0
        var saveError: Error?
        init(_ initial: [KlaviyoRequest] = []) { _stored = initial }

        var stored: [KlaviyoRequest] { lock.lock(); defer { lock.unlock() }; return _stored }
        var saveCount: Int { lock.lock(); defer { lock.unlock() }; return _saveCount }

        func makeIO() -> QueueStore.DiskIO {
            QueueStore.DiskIO(
                load: { [weak self] in self?.stored ?? [] },
                save: { [weak self] requests in
                    guard let self else { return }
                    self.lock.lock(); defer { self.lock.unlock() }
                    self._saveCount += 1
                    if let error = self.saveError { throw error }
                    self._stored = requests
                }
            )
        }
    }

    /// Captures the latest scheduled work so tests can fire it on demand.
    private final class ManualPersistScheduler {
        private var pending: (() -> Void)?
        private(set) var scheduleCount = 0

        func makeScheduler() -> QueueStore.PersistScheduler {
            QueueStore.PersistScheduler { [weak self] _, work in
                self?.scheduleCount += 1
                self?.pending = work
            }
        }

        /// Simulate the debounce interval elapsing for the most recently scheduled work.
        func fire() { let work = pending; pending = nil; work?() }
    }

    private func makeStore(diskIO: SpyDiskIO, scheduler: ManualPersistScheduler,
                           warnings: @escaping (String) -> Void = { _ in }) -> QueueStore {
        QueueStore(diskIO: diskIO.makeIO(),
                   scheduler: scheduler.makeScheduler(), emitWarning: warnings)
    }

    override func setUp() {
        super.setUp()
        SDKConfigStore.shared.reset()
        QueueStore.resetRegistry()
    }

    override func tearDown() {
        SDKConfigStore.shared.reset()
        QueueStore.resetRegistry()
        super.tearDown()
    }

    // MARK: - restore (migration-only, merge-prepend)

    /// `restore` prepends the legacy backlog AHEAD of whatever is already queued rather than
    /// replacing it wholesale, so a request that raced into the queue during the init window
    /// (MAGE-952) survives migration instead of being wiped.
    func testRestorePrependsLegacyAheadOfExistingRequests() throws {
        let diskIO = SpyDiskIO([request("a"), request("b")])
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        try store.restore([request("x"), request("y")])
        XCTAssertEqual(store.requests.map(\.id), ["x", "y", "a", "b"],
                       "legacy backlog goes in front; pre-existing requests are preserved, not wiped")
    }

    /// Calling `restore` twice with the same input (a migration retry) must not duplicate entries.
    func testRestoreCalledTwiceWithSameInputDoesNotDuplicate() throws {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        let requests = [request("a"), request("b")]
        try store.restore(requests)
        try store.restore(requests)
        XCTAssertEqual(store.requests.map(\.id), ["a", "b"])
    }

    func testRestoreWritesSynchronouslyBeforeReturning() throws {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        try store.restore([request("a")])
        XCTAssertEqual(diskIO.saveCount, 1, "restore writes inline, no debounce window")
        XCTAssertEqual(diskIO.stored.map(\.id), ["a"])
    }

    /// A fresh `QueueStore` over the same backing sees the write immediately — the verification
    /// trick migration relies on.
    func testRestorePersistsVisibleToAFreshInstance() throws {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        try store.restore([request("a"), request("b")])

        let freshScheduler = ManualPersistScheduler()
        let freshInstanceOverSameBacking = QueueStore(
            diskIO: diskIO.makeIO(),
            scheduler: freshScheduler.makeScheduler(),
            emitWarning: { _ in }
        )
        XCTAssertEqual(freshInstanceOverSameBacking.requests.map(\.id), ["a", "b"])
    }

    /// A failed save and a genuinely-empty queue both read back as `[]`, so `restore` must throw
    /// rather than let the caller infer success from a read-back.
    func testRestoreThrowsOnSaveFailureAndLeavesMemoryUntouched() {
        let diskIO = SpyDiskIO([request("a")])
        diskIO.saveError = NSError(domain: "disk", code: 1)
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)

        XCTAssertThrowsError(try store.restore([]))
        // Memory must still reflect the last known-good state, not a half-applied restore.
        XCTAssertEqual(store.requests.map(\.id), ["a"])
    }

    /// A failed `restore` must not cancel a pending debounced persist from a concurrent `enqueue`.
    func testFailedRestoreDoesNotCancelPendingDebounce() {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        store.enqueue(request("a")) // schedules a debounced write, generation 1
        XCTAssertEqual(diskIO.saveCount, 0)

        diskIO.saveError = NSError(domain: "disk", code: 1)
        XCTAssertThrowsError(try store.restore([request("x")])) // fails before superseding gen 1

        diskIO.saveError = nil
        scheduler.fire() // generation 1's callback must still be armed and fire normally
        // saveCount is 2: the failed restore attempt itself counts as one save (SpyDiskIO
        // increments before checking the injected error), plus the debounce fire that follows.
        XCTAssertEqual(diskIO.saveCount, 2)
        XCTAssertEqual(diskIO.stored.map(\.id), ["a"], "the pre-restore enqueue's write was not dropped")
    }

    func testRestoreSupersedesPendingDebounce() throws {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        store.enqueue(request("a")) // schedules a debounced write, generation 1
        try store.restore([request("x")]) // writes now, supersedes generation 1
        XCTAssertEqual(diskIO.saveCount, 1)
        scheduler.fire() // stale gen-1 fire must no-op
        XCTAssertEqual(diskIO.saveCount, 1)
        // Merge-prepend: the legacy "x" lands ahead of the already-enqueued "a" (not a wholesale
        // replace), and the write is the merged result.
        XCTAssertEqual(diskIO.stored.map(\.id), ["x", "a"])
    }

    /// Regression: `restore` used to write to disk before taking `queueLock`, so a concurrent
    /// `enqueue` landing in that window got silently overwritten when `restore` reassigned `queue`.
    /// `restore` must now hold `queueLock` across its whole body, so `enqueue` either fully
    /// precedes or fully follows it — proven here by observing `enqueue` block while `restore`'s
    /// (deliberately slow) disk write is in flight.
    func testConcurrentEnqueueDuringRestoreDiskWriteIsNotLost() throws {
        let saveEntered = DispatchSemaphore(value: 0)
        let releaseSave = DispatchSemaphore(value: 0)
        let diskIO = QueueStore.DiskIO(
            load: { [] },
            save: { _ in
                saveEntered.signal()
                releaseSave.wait()
            }
        )
        let store = QueueStore(
            diskIO: diskIO, scheduler: ManualPersistScheduler().makeScheduler(), emitWarning: { _ in }
        )

        Thread { try? store.restore([self.request("x")]) }.start()
        // restore is inside diskIO.save, holding queueLock for its whole body.
        XCTAssertEqual(saveEntered.wait(timeout: .now() + 1), .success)

        let enqueueStarted = DispatchSemaphore(value: 0)
        let enqueueFinished = DispatchSemaphore(value: 0)
        Thread {
            enqueueStarted.signal()
            store.enqueue(self.request("concurrent"))
            enqueueFinished.signal()
        }.start()
        XCTAssertEqual(enqueueStarted.wait(timeout: .now() + 1), .success)
        // enqueue should still be blocked on queueLock, not racing restore's in-flight write.
        XCTAssertEqual(enqueueFinished.wait(timeout: .now() + 0.2), .timedOut,
                       "enqueue must block until restore releases queueLock, not interleave with it")

        releaseSave.signal()
        XCTAssertEqual(enqueueFinished.wait(timeout: .now() + 1), .success)

        XCTAssertEqual(store.requests.map(\.id), ["x", "concurrent"],
                       "the concurrent enqueue must land after restore, never be silently dropped")
    }
}
