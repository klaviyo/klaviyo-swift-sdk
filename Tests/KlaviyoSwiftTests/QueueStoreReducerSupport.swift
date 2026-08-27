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

/// Backs `QueueStore.store(for:)` with an in-memory queue for reducer tests, since the reducer
/// resolves the production disk-backed store and `.test` file stubs are no-ops. Returns the
/// live backing array getter so tests can assert queue contents.
@discardableResult
func seedTestQueueStore(apiKey: String, initial: [KlaviyoRequest] = []) -> () -> [KlaviyoRequest] {
    QueueStore.resetRegistry()
    return registerTestQueueStore(apiKey: apiKey, initial: initial)
}

/// Registers an additional in-memory spy store for `apiKey` WITHOUT clearing the registry, so a
/// test that exercises more than one apiKey (e.g. a company switch) can back each key's queue.
@discardableResult
func registerTestQueueStore(apiKey: String, initial: [KlaviyoRequest] = []) -> () -> [KlaviyoRequest] {
    var stored = initial
    let lock = NSLock()
    let io = QueueStore.DiskIO(
        load: { lock.lock(); defer { lock.unlock() }; return stored },
        save: { new in lock.lock(); defer { lock.unlock() }; stored = new }
    )
    // Fire debounced persists immediately so tests observe writes without wall-clock waits.
    let scheduler = QueueStore.PersistScheduler { _, work in work() }
    let store = QueueStore(diskIO: io, scheduler: scheduler, emitWarning: { _ in })
    QueueStore.register(store, for: apiKey)
    return { lock.lock(); defer { lock.unlock() }; return stored }
}

/// Registers a recording spy `QueueStore` for `apiKey` that accumulates every request ever
/// persisted (appending each `save` call), so drain-then-flush sequences are fully observable.
/// Resets the registry first (like `seedTestQueueStore`) — call before other registrations.
/// Returns a closure that reads the accumulated recorded batches.
@discardableResult
func registerRecordingQueueStore(apiKey: String) -> () -> [KlaviyoRequest] {
    let recorded = ThreadSafeBox<[KlaviyoRequest]>([])
    QueueStore.resetRegistry()
    let io = QueueStore.DiskIO(
        load: { [] },
        save: { new in recorded.mutate { $0.append(contentsOf: new) } }
    )
    let spy = QueueStore(
        diskIO: io,
        scheduler: QueueStore.PersistScheduler { _, work in work() },
        emitWarning: { _ in }
    )
    QueueStore.register(spy, for: apiKey)
    return { recorded.value }
}
