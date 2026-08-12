//
//  QueueStoreTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/4/26.
//

@testable import KlaviyoCore
import XCTest

final class QueueStoreTests: XCTestCase {
    private func request(_ id: String, priority: RequestPriority = .standard,
                         at date: Date = Date(timeIntervalSince1970: 0)) -> KlaviyoRequest {
        KlaviyoRequest(
            id: id,
            endpoint: .createProfile("foo", CreateProfilePayload(data: .test)),
            enqueuedAt: date,
            priority: priority
        )
    }

    func testPersistedQueueRoundTrips() throws {
        let original = PersistedQueue(requests: [request("a"), request("b", priority: .high)])
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"version\""), "on-disk JSON must carry the version key")
        let decoded = try JSONDecoder().decode(PersistedQueue.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.version, 1)
    }

    // MARK: - Test doubles

    /// Thread-safe in-memory DiskIO that counts loads/saves for assertions. Locking keeps the
    /// spy sound under the concurrent-persist test; single-threaded tests are unaffected.
    private final class SpyDiskIO {
        private let lock = NSLock()
        private var _stored: [KlaviyoRequest]
        private var _loadCount = 0
        private var _saveCount = 0
        var loadError: Error?
        var saveError: Error?
        init(_ initial: [KlaviyoRequest] = []) { _stored = initial }

        var stored: [KlaviyoRequest] { lock.lock(); defer { lock.unlock() }; return _stored }
        var loadCount: Int { lock.lock(); defer { lock.unlock() }; return _loadCount }
        var saveCount: Int { lock.lock(); defer { lock.unlock() }; return _saveCount }

        func makeIO() -> QueueStore.DiskIO {
            QueueStore.DiskIO(
                load: { [weak self] in
                    guard let self else { return [] }
                    self.lock.lock(); defer { self.lock.unlock() }
                    self._loadCount += 1
                    if let error = self.loadError { throw error }
                    return self._stored
                },
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

    // MARK: - enqueue ordering + persistence

    func testStandardEnqueueAppends() {
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: SpyDiskIO(), scheduler: scheduler)
        store.enqueue(request("a"))
        store.enqueue(request("b"))
        XCTAssertEqual(store.requests.map(\.id), ["a", "b"])
    }

    func testHighPriorityFrontInsertsNewestFirst() {
        let store = makeStore(diskIO: SpyDiskIO(), scheduler: ManualPersistScheduler())
        store.enqueue(request("a"))
        store.enqueue(request("b"))
        store.enqueue(request("c", priority: .high))
        store.enqueue(request("d", priority: .high))
        XCTAssertEqual(store.requests.map(\.id), ["d", "c", "a", "b"])
    }

    func testDebouncedEnqueueSchedulesButDoesNotWriteUntilFired() {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        store.enqueue(request("a"))
        XCTAssertEqual(diskIO.saveCount, 0, "debounced write not yet flushed")
        scheduler.fire()
        XCTAssertEqual(diskIO.saveCount, 1)
        XCTAssertEqual(diskIO.stored.map(\.id), ["a"])
    }

    func testSynchronousEnqueueWritesImmediately() {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        store.enqueue(request("a"), persist: .synchronous)
        XCTAssertEqual(diskIO.saveCount, 1, "synchronous write happens inline")
        XCTAssertEqual(diskIO.stored.map(\.id), ["a"])
    }

    // MARK: - Hydrate-once

    func testHydratesOnceThenServesFromMemory() {
        let diskIO = SpyDiskIO([request("a"), request("b")])
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler())

        XCTAssertEqual(store.requests.map(\.id), ["a", "b"])
        XCTAssertEqual(store.count, 2)
        _ = store.requests
        XCTAssertEqual(diskIO.loadCount, 1, "disk read only on first access")
    }

    // MARK: - Persist error handling

    func testSynchronousPersistFailureEmitsWarning() {
        let diskIO = SpyDiskIO()
        diskIO.saveError = NSError(domain: "disk", code: 1)
        var warnings: [String] = []
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler(),
                              warnings: { warnings.append($0) })
        store.enqueue(request("a"), persist: .synchronous)
        XCTAssertTrue(warnings.contains { $0.contains("persist") },
                      "a persist failure must emit a developer warning")
    }

    // MARK: - Bounded size

    func testEnqueueEvictsOldestByEnqueuedAtAtCapacity() {
        let diskIO = SpyDiskIO((0..<QueueStore.maxQueueSize).map {
            request("req-\($0)", at: Date(timeIntervalSince1970: TimeInterval($0)))
        })
        var warnings: [String] = []
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler(),
                              warnings: { warnings.append($0) })

        store.enqueue(request("new", at: Date(timeIntervalSince1970: 10_000)))

        XCTAssertEqual(store.count, QueueStore.maxQueueSize)
        XCTAssertEqual(store.requests.first?.id, "req-1", "req-0 (oldest) evicted")
        XCTAssertEqual(store.requests.last?.id, "new")
        XCTAssertEqual(warnings.count, 1)
    }

    // MARK: - prepend / restore-to-front

    func testPrependInsertsBatchAtHeadPreservingOrder() {
        let diskIO = SpyDiskIO([request("a"), request("b"), request("c")])
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler())
        store.prepend([request("x"), request("y")])
        XCTAssertEqual(store.requests.map(\.id), ["x", "y", "a", "b", "c"])
    }

    func testPrependDoesNotEvictAndMayExceedCap() {
        let diskIO = SpyDiskIO((0..<QueueStore.maxQueueSize).map { request("req-\($0)") })
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler())
        store.prepend([request("restored")])
        XCTAssertEqual(store.count, QueueStore.maxQueueSize + 1,
                       "restore may transiently exceed cap")
        XCTAssertEqual(store.requests.first?.id, "restored")
    }

    // MARK: - Eventual cap (PR #627 parity)

    func testOverCapacityFromPrependHealsOnNextEnqueue() {
        let overCapacity = QueueStore.maxQueueSize + 25
        let diskIO = SpyDiskIO((0..<overCapacity).map {
            request("req-\($0)", at: Date(timeIntervalSince1970: TimeInterval($0)))
        })
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler())
        XCTAssertEqual(store.count, overCapacity, "hydrates over-cap without eviction")

        store.enqueue(request("new", at: Date(timeIntervalSince1970: 100_000)))

        XCTAssertEqual(store.count, QueueStore.maxQueueSize, "single enqueue drains back to the cap")
        XCTAssertEqual(store.requests.last?.id, "new")
        // The 26 oldest (req-0…req-25) are evicted; req-26 becomes the head.
        XCTAssertEqual(store.requests.first?.id, "req-26")
    }

    // MARK: - Debounce coalescing

    func testBurstOfEnqueuesCoalescesToSingleWrite() {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        store.enqueue(request("a"))
        store.enqueue(request("b"))
        store.enqueue(request("c"))
        scheduler.fire()
        XCTAssertEqual(diskIO.saveCount, 1, "coalesced to one write")
        XCTAssertEqual(diskIO.stored.map(\.id), ["a", "b", "c"], "write carries final state")
    }

    /// Regression guard for the durability of `.synchronous`: a debounced write scheduled
    /// *before* a later synchronous write must not clobber it when it eventually fires.
    func testSynchronousSupersedesPendingDebounce() {
        let diskIO = SpyDiskIO()
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: diskIO, scheduler: scheduler)
        store.enqueue(request("a")) // schedules debounced (generation 1)
        store.enqueue(request("b"), persist: .synchronous) // writes now, bumps to generation 2
        XCTAssertEqual(diskIO.saveCount, 1)
        scheduler.fire() // stale gen-1 fire is superseded → no-ops, no stale overwrite
        XCTAssertEqual(diskIO.saveCount, 1)
        XCTAssertEqual(diskIO.stored.map(\.id), ["a", "b"])
    }

    /// Regression guard for the lost-write race (concurrent mutation vs. persist ordering):
    /// under many concurrent synchronous enqueues, disk must converge to in-memory state.
    /// Persisting the *current* queue at write time (rather than a snapshot captured at schedule
    /// time) makes disk order-independent of `persistLock` acquisition order.
    func testConcurrentSynchronousEnqueuesConvergeDiskToMemory() {
        let iterations = 100 // < maxQueueSize, so no eviction
        let diskIO = SpyDiskIO()
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler())

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            store.enqueue(
                request("req-\(index)", at: Date(timeIntervalSince1970: TimeInterval(index))),
                persist: .synchronous
            )
        }

        XCTAssertEqual(store.count, iterations)
        XCTAssertEqual(diskIO.stored.map(\.id), store.requests.map(\.id),
                       "disk must match the in-memory queue exactly — no lost or reordered writes")
    }

    func testProductionSchedulerRunsScheduledWork() {
        let didRun = expectation(description: "scheduled work ran")
        QueueStore.PersistScheduler.production.schedule(0.01) { didRun.fulfill() }
        wait(for: [didRun], timeout: 1.0)
    }

    // MARK: - Corrupt / absent

    func testCorruptLoadHydratesToEmpty() {
        let diskIO = SpyDiskIO()
        diskIO.loadError = NSError(domain: "corrupt", code: 1)
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler())
        XCTAssertEqual(store.requests, [])
    }

    // MARK: - current() resolver

    func testCurrentReturnsNilWithoutApiKey() {
        XCTAssertNil(QueueStore.current())
    }

    func testCurrentResolvesApiKeyAndCachesByKey() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "company-xyz"))
        let first = QueueStore.current()
        let second = QueueStore.current()
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "same instance cached per apiKey")
    }
}
