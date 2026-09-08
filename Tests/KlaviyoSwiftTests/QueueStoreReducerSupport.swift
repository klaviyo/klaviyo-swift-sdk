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

/// Backs the shared `QueueStore` with an in-memory queue for reducer tests, since the reducer
/// resolves the production disk-backed store and `.test` file stubs are no-ops. Returns the
/// live backing array getter so tests can assert queue contents.
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
    let io = QueueStore.DiskIO(
        load: { lock.lock(); defer { lock.unlock() }; return stored },
        save: { new in lock.lock(); defer { lock.unlock() }; stored = new }
    )
    // Fire debounced persists immediately so tests observe writes without wall-clock waits.
    let scheduler = QueueStore.PersistScheduler { _, work in work() }
    let store = QueueStore(diskIO: io, scheduler: scheduler, emitWarning: { _ in })
    QueueStore.register(store)
    return { lock.lock(); defer { lock.unlock() }; return stored }
}

/// Registers a recording spy `QueueStore` that accumulates every request ever persisted
/// (appending each `save` call), so drain-then-flush sequences are fully observable. Resets the
/// shared store first (like `seedTestQueueStore`) — call before other registrations.
/// Returns a closure that reads the accumulated recorded batches.
@discardableResult
func registerRecordingQueueStore() -> () -> [KlaviyoRequest] {
    let recorded = ThreadSafeBox<[KlaviyoRequest]>([])
    QueueStore.resetShared()
    let io = QueueStore.DiskIO(
        load: { [] },
        save: { new in recorded.mutate { $0.append(contentsOf: new) } }
    )
    let spy = QueueStore(
        diskIO: io,
        scheduler: QueueStore.PersistScheduler { _, work in work() },
        emitWarning: { _ in }
    )
    QueueStore.register(spy)
    return { recorded.value }
}
