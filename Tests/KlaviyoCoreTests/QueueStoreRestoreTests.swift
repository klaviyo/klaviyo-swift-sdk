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

    // MARK: - restore (migration-only, full replace)

    func testRestoreReplacesWholesaleRatherThanInserting() throws {
        let diskIO = SpyDiskIO([request("a"), request("b")])
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        try store.restore([request("x"), request("y")])
        XCTAssertEqual(store.requests.map(\.id), ["x", "y"], "replaces, does not prepend/append")
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
        XCTAssertEqual(diskIO.stored.map(\.id), ["x"])
    }
}
