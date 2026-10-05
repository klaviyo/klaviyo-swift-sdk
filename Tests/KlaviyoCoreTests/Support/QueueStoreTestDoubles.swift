//
//  QueueStoreTestDoubles.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Foundation

/// Thread-safe in-memory DiskIO that counts loads/saves for assertions. Locking keeps the
/// spy sound under concurrent-persist tests; single-threaded tests are unaffected.
final class SpyDiskIO {
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
final class ManualPersistScheduler {
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
