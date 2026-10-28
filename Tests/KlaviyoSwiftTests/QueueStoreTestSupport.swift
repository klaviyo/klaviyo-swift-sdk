@testable import KlaviyoCore
import Foundation

/// Minimal lock-guarded box for collecting values across the concurrent API-send closure in tests.
final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ transform: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }; transform(&stored)
    }
}

/// Backs the shared `QueueStore` with an in-memory queue for orchestration tests, since the
/// production disk-backed store and `.test` file stubs are no-ops. Returns the live backing
/// array getter so tests can assert queue contents.
@discardableResult
func seedTestQueueStore(initial: [KlaviyoRequest] = []) -> () -> [KlaviyoRequest] {
    QueueStore.resetShared()
    return registerTestQueueStore(initial: initial)
}

/// Registers an in-memory spy as the single shared QueueStore, replacing whatever was there.
/// Prefer `seedTestQueueStore`, which resets first.
@discardableResult
private func registerTestQueueStore(initial: [KlaviyoRequest] = []) -> () -> [KlaviyoRequest] {
    var stored = initial
    let lock = NSLock()
    let diskIO = QueueStore.DiskIO(
        load: { lock.lock(); defer { lock.unlock() }; return stored },
        save: { snapshot in lock.lock(); defer { lock.unlock() }; stored = snapshot }
    )
    // Fire debounced persists immediately so tests observe writes without wall-clock waits.
    let scheduler = QueueStore.PersistScheduler { _, work in work() }
    let store = QueueStore(diskIO: diskIO, scheduler: scheduler, emitWarning: { _ in })
    QueueStore.register(store)
    return { lock.lock(); defer { lock.unlock() }; return stored }
}

/// Registers a shared `QueueStore` whose debounced persists are DEFERRED (the scheduled work is
/// captured but never run), so a test can distinguish `.synchronous` (writes to disk immediately)
/// from `.debounced` (stays in memory until a debounce that never fires here). Returns a closure
/// reading what has actually reached disk. Resets the shared store first.
@discardableResult
func seedDeferredPersistQueueStore() -> () -> [KlaviyoRequest] {
    QueueStore.resetShared()
    var stored: [KlaviyoRequest] = []
    let lock = NSLock()
    let diskIO = QueueStore.DiskIO(
        load: { lock.lock(); defer { lock.unlock() }; return stored },
        save: { snapshot in lock.lock(); defer { lock.unlock() }; stored = snapshot }
    )
    let scheduler = QueueStore.PersistScheduler { _, _ in } // never run debounced work
    let store = QueueStore(diskIO: diskIO, scheduler: scheduler, emitWarning: { _ in })
    QueueStore.register(store)
    return { lock.lock(); defer { lock.unlock() }; return stored }
}

/// Registers a recording spy `QueueStore` that accumulates every request ever persisted
/// (deduplicated by full value, first-seen order preserved), so drain-then-flush sequences are
/// fully observable without one request being re-recorded on every later `save` of the whole queue.
/// Deduplicating by value rather than by `id` alone matters under the fixed test `environment.uuid`:
/// two distinct enqueues can default to the same `id` there (production always mints a fresh one),
/// and an id-only dedup would silently drop the second as a false repeat of the first. Resets the
/// shared store first (like `seedTestQueueStore`) — call before other registrations. Returns a
/// closure that reads the accumulated recorded requests.
@discardableResult
func registerRecordingQueueStore() -> () -> [KlaviyoRequest] {
    let recorded = ThreadSafeBox<[KlaviyoRequest]>([])
    QueueStore.resetShared()
    let diskIO = QueueStore.DiskIO(
        load: { [] },
        save: { snapshot in
            recorded.mutate { seen in
                seen.append(contentsOf: snapshot.filter { !seen.contains($0) })
            }
        }
    )
    let spyStore = QueueStore(
        diskIO: diskIO,
        scheduler: QueueStore.PersistScheduler { _, work in work() },
        emitWarning: { _ in }
    )
    QueueStore.register(spyStore)
    return { recorded.value }
}
