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

    // MARK: - Production file location

    func testProductionDiskIORoutesQueueFileToApplicationSupport() throws {
        let appSupportRoot = URL(fileURLWithPath: "/tmp/klaviyo-queue-tests/app-support")
        let libraryRoot = URL(fileURLWithPath: "/tmp/klaviyo-queue-tests/library")
        var capturedURL: URL?

        let previous = environment
        defer { environment = previous }
        environment = KlaviyoEnvironment.test()
        environment.fileClient = FileClient(
            write: { _, url in capturedURL = url },
            fileExists: { _ in false },
            removeItem: { _ in },
            libraryDirectory: { libraryRoot },
            applicationSupportDirectory: { appSupportRoot }
        )

        try QueueStore.DiskIO.production(apiKey: "abc123").save([])

        // The queue file must land under Application Support, not the legacy Library root.
        XCTAssertEqual(capturedURL, appSupportRoot.appendingPathComponent("klaviyo-abc123-queue.json"))
        XCTAssertFalse(capturedURL?.path.hasPrefix(libraryRoot.path) ?? true)
    }

    func testProductionApplicationSupportDirectoryIsNamespacedUnderApplicationSupport() {
        let url = productionApplicationSupportDirectory()
        XCTAssertEqual(url.lastPathComponent, "com.klaviyo")
        XCTAssertTrue(url.deletingLastPathComponent().path.hasSuffix("Application Support"))
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

    func testLoadFailureEmitsWarningAndFallsBackToEmpty() {
        let diskIO = SpyDiskIO([request("a")])
        diskIO.loadError = NSError(domain: "disk", code: 2)
        var warnings: [String] = []
        let store = makeStore(diskIO: diskIO, scheduler: ManualPersistScheduler(),
                              warnings: { warnings.append($0) })
        XCTAssertEqual(store.requests, [], "a load failure falls back to an empty queue")
        XCTAssertTrue(warnings.contains { $0.contains("failed to load") },
                      "a load failure must emit a developer warning rather than silently empty")
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

    func testBurstOfDebouncedEnqueuesSchedulesSingleCallback() {
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: SpyDiskIO(), scheduler: scheduler)
        store.enqueue(request("a"))
        store.enqueue(request("b"))
        store.enqueue(request("c"))
        XCTAssertEqual(scheduler.scheduleCount, 1,
                       "a debounced burst coalesces to one scheduled callback, not one per mutation")
    }

    func testDebounceReschedulesAfterPreviousWindowFires() {
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: SpyDiskIO(), scheduler: scheduler)
        store.enqueue(request("a"))
        scheduler.fire() // window closes
        store.enqueue(request("b")) // new window → schedules again
        XCTAssertEqual(scheduler.scheduleCount, 2, "a fresh mutation after a fired window reschedules")
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

    /// Mixed-policy sibling of the convergence test: `.debounced` and `.synchronous` mutations run
    /// concurrently, contending on `queueLock` (the array) and `persistLock` (the debounce-coalescing
    /// state) at once. Debounced work is dropped by the scheduler; a final synchronous flush then
    /// persists the settled queue, and disk must match memory exactly — no lost, duplicated, or
    /// reordered writes from the interleaving. Meaningful under Thread Sanitizer.
    func testConcurrentMixedPersistPoliciesConvergeOnFinalSyncFlush() {
        let iterations = 100 // < maxQueueSize, so no eviction
        let diskIO = SpyDiskIO()
        // Drop debounced work; convergence is forced deterministically by the final synchronous flush.
        let store = QueueStore(diskIO: diskIO.makeIO(),
                               scheduler: QueueStore.PersistScheduler { _, _ in },
                               emitWarning: { _ in })

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let policy: PersistPolicy = index.isMultiple(of: 2) ? .debounced : .synchronous
            store.enqueue(
                request("req-\(index)", at: Date(timeIntervalSince1970: TimeInterval(index))),
                persist: policy
            )
        }

        // Flush the settled in-memory queue to disk after all concurrent work has joined.
        store.enqueue(
            request("flush", at: Date(timeIntervalSince1970: TimeInterval(iterations))),
            persist: .synchronous
        )

        XCTAssertEqual(store.count, iterations + 1)
        XCTAssertEqual(diskIO.stored.map(\.id), store.requests.map(\.id),
                       "after a final synchronous flush, disk matches the in-memory queue exactly")
    }

    /// Stresses the static `registryLock`: many threads resolve `current()` for the same apiKey and
    /// must all receive the one cached instance — no torn read that mints a duplicate store.
    func testConcurrentCurrentResolvesSingleCachedInstance() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "concurrent-key"))
        let collectLock = UnfairLock()
        var resolved: [QueueStore] = []

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            if let store = QueueStore.current() {
                collectLock.withLock { resolved.append(store) }
            }
        }

        XCTAssertEqual(resolved.count, 200, "every resolution returned a store")
        let first = resolved.first
        XCTAssertTrue(resolved.allSatisfy { $0 === first }, "all resolutions share one cached instance")
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

    // MARK: - drainAll

    func testDrainAllReturnsAndClearsQueue() {
        let disk = SpyDiskIO([request("a"), request("b")])
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: disk, scheduler: scheduler)

        let drained = store.drainAll()

        XCTAssertEqual(drained.map(\.id), ["a", "b"], "drainAll returns the full queue in order")
        XCTAssertEqual(store.requests, [], "queue is empty after drain")
    }

    func testDrainAllOnEmptyQueueReturnsEmptyAndStillSchedulesPersist() {
        let disk = SpyDiskIO([])
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: disk, scheduler: scheduler)

        XCTAssertEqual(store.drainAll(), [])
        // Debounced persist scheduled even for an empty drain (parity with today's removeAll save).
        XCTAssertEqual(scheduler.scheduleCount, 1)
    }

    func testDrainAllPersistsClearedQueueWhenDebounceFires() {
        let disk = SpyDiskIO([request("a")])
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: disk, scheduler: scheduler)

        _ = store.drainAll()
        scheduler.fire()

        XCTAssertEqual(disk.stored, [], "cleared queue is written to disk on debounce fire")
    }

    func testDrainAllSynchronousPersistsImmediately() {
        let disk = SpyDiskIO([request("a")])
        let scheduler = ManualPersistScheduler()
        let store = makeStore(diskIO: disk, scheduler: scheduler)

        _ = store.drainAll(persist: .synchronous)

        XCTAssertEqual(disk.stored, [], "synchronous drain writes the empty queue before returning")
        XCTAssertEqual(scheduler.scheduleCount, 0, "synchronous persist does not schedule a debounce")
    }

    // MARK: - register injection seam

    func testRegisterInjectsStoreForApiKey() {
        QueueStore.resetRegistry()
        defer { QueueStore.resetRegistry() }
        let disk = SpyDiskIO([request("seeded")])
        let injected = makeStore(diskIO: disk, scheduler: ManualPersistScheduler())

        QueueStore.register(injected, for: "abc")

        XCTAssertTrue(QueueStore.store(for: "abc") === injected,
                      "store(for:) returns the injected instance")
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
