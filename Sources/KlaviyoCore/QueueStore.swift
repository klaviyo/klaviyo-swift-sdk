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
/// changes can be handled as additive migrations.
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

    /// Coalescing window for `.debounced` persistence.
    static let debounceInterval: TimeInterval = 1.0

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

    /// Timing seam for debounced persistence. Injected so tests drive persistence
    /// deterministically without wall-clock delays. Mirrors the `DiskIO` closure-seam idiom.
    public struct PersistScheduler {
        /// Run `work` after `delay` seconds. Fire-and-forget: coalescing is handled by
        /// `QueueStore`'s pending-debounce token, so there is no cancellation to manage here.
        public var schedule: (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void
        public init(schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void) {
            self.schedule = schedule
        }

        /// Production scheduler: each accessor gets its own serial queue, so the store that
        /// captures it at init keeps its writes ordered. (Each store captures this exactly once;
        /// distinct apiKey stores write distinct files, so they need no shared ordering.)
        static var production: Self {
            let queue = DispatchQueue(label: "com.klaviyo.queuestore.persist")
            return Self { delay, work in
                queue.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }
    }

    private let diskIO: DiskIO
    private let scheduler: PersistScheduler
    private let emitWarning: (String) -> Void

    // guards `queue`; released before disk writes so I/O never blocks queue ops
    private let queueLock = NSLock()
    private let persistLock = NSLock() // serializes writes + guards the debounce-coalescing state
    private var queue: [KlaviyoRequest]? // nil until hydrated; authoritative once loaded
    // Coalesces `.debounced` persists: the first mutation in a window schedules one callback and
    // records its token here; later debounced mutations within the window coalesce onto it instead
    // of scheduling their own. A synchronous persist — or the callback firing — clears it. `0` means
    // no debounce is pending. `debounceSeq` mints unique tokens so a superseded callback can tell it
    // is no longer the current one and no-op.
    private var pendingDebounceToken = 0
    private var debounceSeq = 0

    /// Ungated production entry point: one store per apiKey, backed by that key's queue file.
    public convenience init(apiKey: String) {
        self.init(diskIO: .production(apiKey: apiKey),
                  scheduler: .production,
                  emitWarning: { environment.emitDeveloperWarning($0) })
    }

    init(diskIO: DiskIO, scheduler: PersistScheduler,
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
        queueLock.unlock()
        schedulePersist(persist)
    }

    public func prepend(_ requests: [KlaviyoRequest],
                        persist: PersistPolicy = .debounced) {
        guard !requests.isEmpty else { return }
        queueLock.lock()
        var next = hydrated()
        next.insert(contentsOf: requests, at: 0) // deliberately no eviction — see evictIfAtCapacity
        queue = next
        queueLock.unlock()
        schedulePersist(persist)
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

    /// Either flushes inline (`.synchronous`) or schedules one debounced flush per window
    /// (`.debounced`). A debounced burst coalesces to a single scheduled callback: only the first
    /// mutation schedules, later ones piggyback on the pending token. A synchronous persist clears
    /// the pending token so its still-scheduled callback no-ops when it fires. Coalescing is only an
    /// optimization — correctness comes from `persistCurrent`, which always writes the current
    /// authoritative queue, so a superseded fire can never persist stale state.
    private func schedulePersist(_ policy: PersistPolicy) {
        switch policy {
        case .synchronous:
            persistLock.lock()
            pendingDebounceToken = 0 // supersede any pending debounce; its callback will no-op
            persistLock.unlock()
            persistCurrent()
        case .debounced:
            persistLock.lock()
            guard pendingDebounceToken == 0 else { persistLock.unlock(); return } // coalesce
            debounceSeq &+= 1
            let token = debounceSeq
            pendingDebounceToken = token
            persistLock.unlock()
            scheduler.schedule(Self.debounceInterval) { [weak self] in
                guard let self else { return }
                self.persistLock.lock()
                let isCurrent = self.pendingDebounceToken == token
                if isCurrent { self.pendingDebounceToken = 0 }
                self.persistLock.unlock()
                guard isCurrent else { return } // superseded → coalesced away
                self.persistCurrent()
            }
        }
    }

    /// Serializes the whole persist under `persistLock` and snapshots the *current* authoritative
    /// queue at write time. Because every persist reads the latest memory and writes are serialized,
    /// disk always converges to the newest state — there is no captured snapshot that can go stale.
    /// `queueLock` is released before the disk write so I/O never blocks queue ops.
    private func persistCurrent() {
        persistLock.lock(); defer { persistLock.unlock() }
        queueLock.lock()
        let snapshot = queue ?? []
        queueLock.unlock()
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
    /// or `nil` if no apiKey is set yet (buffering pre-apiKey events is handled elsewhere).
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
            environment.fileClient.applicationSupportDirectory()
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
