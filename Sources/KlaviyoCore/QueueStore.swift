//
//  QueueStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/4/26.
//

import Foundation

/// How a `QueueStore` mutation is persisted.
public enum PersistPolicy {
    /// Coalesced 1-second write (default; matches today's behavior).
    case debounced
    /// Inline blocking write before returning — for durability-critical writes.
    case synchronous
}

/// On-disk shape of the queue file. Carries a `version` affordance so future format
/// changes are additive migrations (MAGE-954).
struct PersistedQueue: Codable, Equatable {
    static let currentVersion = 1
    var version: Int
    var requests: [KlaviyoRequest]

    init(version: Int = PersistedQueue.currentVersion, requests: [KlaviyoRequest]) {
        self.version = version
        self.requests = requests
    }
}

public final class QueueStore {
    public static let maxQueueSize = 200

    /// Disk-I/O seam. Production reads/writes `klaviyo-{apiKey}-queue.json`; tests inject a fake.
    public struct DiskIO {
        public var load: () throws -> [KlaviyoRequest]
        public var save: ([KlaviyoRequest]) throws -> Void
        public init(load: @escaping () throws -> [KlaviyoRequest],
                    save: @escaping ([KlaviyoRequest]) throws -> Void) {
            self.load = load
            self.save = save
        }
    }

    private let diskIO: DiskIO
    private let scheduler: QueuePersistScheduler
    private let emitWarning: (String) -> Void

    // guards `queue`; held during the one-time hydrate read, never during persist writes
    private let queueLock = NSLock()
    private let persistLock = NSLock() // serializes actual writes + the pending token
    private var queue: [KlaviyoRequest]? // nil until hydrated; authoritative once loaded
    private var pendingPersist: QueuePersistToken?

    /// Ungated production entry point: one store per apiKey, backed by that key's queue file.
    public convenience init(apiKey: String) {
        self.init(apiKey: apiKey,
                  diskIO: .production(apiKey: apiKey),
                  scheduler: DispatchQueuePersistScheduler(),
                  emitWarning: { environment.emitDeveloperWarning($0) })
    }

    init(apiKey _: String, diskIO: DiskIO, scheduler: QueuePersistScheduler,
         emitWarning: @escaping (String) -> Void) {
        self.diskIO = diskIO
        self.scheduler = scheduler
        self.emitWarning = emitWarning
    }

    // MARK: Mutations

    public func enqueue(_ request: KlaviyoRequest, persist: PersistPolicy = .debounced) {
        queueLock.lock()
        var next = hydrated()
        evictIfAtCapacity(&next)
        if request.priority == .high {
            next.insert(request, at: 0)
        } else {
            next.append(request)
        }
        queue = next
        let snapshot = next
        queueLock.unlock()
        schedulePersist(snapshot, persist)
    }

    public func prepend(_ requests: [KlaviyoRequest],
                        persist: PersistPolicy = .debounced) {
        guard !requests.isEmpty else { return }
        queueLock.lock()
        var next = hydrated()
        next.insert(contentsOf: requests, at: 0) // deliberately no eviction — see evictIfAtCapacity
        queue = next
        let snapshot = next
        queueLock.unlock()
        schedulePersist(snapshot, persist)
    }

    /// Drains oldest-by-`enqueuedAt` while at/over capacity, leaving room for one insert.
    /// Loops (not a single removal) so an over-capacity queue produced by `prepend`/restore
    /// self-heals on the next enqueue. Parity with `KlaviyoState.evictOldestIfAtCapacity`.
    private func evictIfAtCapacity(_ queue: inout [KlaviyoRequest]) {
        guard queue.count >= Self.maxQueueSize else { return }
        emitWarning(
            "Request queue at capacity (\(Self.maxQueueSize)); "
                + "evicting oldest request(s) to make room."
        )
        while queue.count >= Self.maxQueueSize,
              let oldest = queue.indices.min(
                  by: { queue[$0].enqueuedAt < queue[$1].enqueuedAt }
              ) {
            queue.remove(at: oldest)
        }
    }

    // MARK: Persistence

    /// Updates the pending write and either schedules it (debounced) or performs it inline
    /// (synchronous). Holds `persistLock` — never `queueLock` — so disk I/O never blocks queue ops.
    private func schedulePersist(_ snapshot: [KlaviyoRequest], _ policy: PersistPolicy) {
        persistLock.lock(); defer { persistLock.unlock() }
        pendingPersist?.cancel()
        pendingPersist = nil
        switch policy {
        case .debounced:
            pendingPersist = scheduler.schedule(after: 1.0) { [weak self] in
                self?.write(snapshot)
            }
        case .synchronous:
            persistSnapshot(snapshot)
        }
    }

    /// Debounced fire path: acquires `persistLock` itself (it runs later, off the scheduler).
    private func write(_ snapshot: [KlaviyoRequest]) {
        persistLock.lock(); defer { persistLock.unlock() }
        persistSnapshot(snapshot)
    }

    /// Persists the snapshot. Caller must hold `persistLock`.
    private func persistSnapshot(_ snapshot: [KlaviyoRequest]) {
        do {
            try diskIO.save(snapshot)
        } catch {
            emitWarning("QueueStore: failed to persist queue (\(error))")
        }
    }

    // MARK: Reads

    public var requests: [KlaviyoRequest] {
        queueLock.lock(); defer { queueLock.unlock() }
        return hydrated()
    }

    public var count: Int {
        queueLock.lock(); defer { queueLock.unlock() }
        return hydrated().count
    }

    /// Loads from disk on first access; memory is authoritative thereafter. Call under `queueLock`.
    private func hydrated() -> [KlaviyoRequest] {
        if let queue { return queue }
        let loaded = (try? diskIO.load()) ?? []
        queue = loaded
        return loaded
    }
}

extension QueueStore {
    private static let registryLock = NSLock()
    private static var registry: [String: QueueStore] = [:]

    /// Resolves the current apiKey from `SDKConfigStore` and returns the (cached) store for it,
    /// or `nil` if no apiKey is set yet (pre-apiKey buffering is MAGE-951's concern).
    public static func current() -> QueueStore? {
        guard let apiKey = SDKConfigStore.shared.current.apiKey else { return nil }
        registryLock.lock(); defer { registryLock.unlock() }
        if let existing = registry[apiKey] { return existing }
        let store = QueueStore(apiKey: apiKey)
        registry[apiKey] = store
        return store
    }

    /// Test-support: clears the per-apiKey instance cache.
    package static func resetRegistry() {
        registryLock.lock(); defer { registryLock.unlock() }
        registry.removeAll()
    }
}

extension QueueStore.DiskIO {
    static func production(apiKey: String) -> Self {
        func fileURL() -> URL {
            environment.fileClient.libraryDirectory()
                .appendingPathComponent("klaviyo-\(apiKey)-queue.json", isDirectory: false)
        }
        return Self(
            load: {
                let queueURL = fileURL()
                guard environment.fileClient.fileExists(queueURL.path) else { return [] }
                let data = try environment.dataFromUrl(queueURL)
                let decoded: PersistedQueue = try environment.decoder.decode(data)
                return decoded.requests
            },
            save: { requests in
                let data = try environment.encodeJSON(PersistedQueue(requests: requests))
                try environment.fileClient.write(data, fileURL())
            }
        )
    }
}
