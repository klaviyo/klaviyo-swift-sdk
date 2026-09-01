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

    // Two locks keep slow disk I/O off the hot queue path: `queueLock` guards the in-memory array
    // and is released before any disk write, so a persist never blocks enqueue/prepend/reads.
    // `persistLock` serializes writes and guards the debounce-coalescing state. `restore` is the
    // one exception — see its doc comment for why it holds `queueLock` across its disk write too.
    //
    // LOCK ORDERING: when both are held, always acquire `persistLock` before `queueLock`, never the
    // reverse. `persistCurrent` and `restore` are the only nesting sites (persistLock outer,
    // queueLock inner); every other site takes exactly one lock. Preserve this order to stay
    // deadlock-free.
    private let queueLock = UnfairLock()
    private let persistLock = UnfairLock()
    private var queue: [KlaviyoRequest]? // nil until hydrated; authoritative once loaded
    // Debounce-coalescing state (guarded by `persistLock`). `pendingDebounceToken` is the token of the
    // window's scheduled callback, or `0` when none is pending; `debounceSeq` mints unique tokens.
    // See `schedulePersist` for how a burst coalesces onto a single callback.
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
        queueLock.withLock {
            var next = hydrated()
            evictIfAtCapacity(&next)
            if request.priority == .high {
                next.insert(request, at: 0)
            } else {
                next.append(request)
            }
            queue = next
        }
        schedulePersist(persist)
    }

    public func prepend(_ requests: [KlaviyoRequest],
                        persist: PersistPolicy = .debounced) {
        guard !requests.isEmpty else { return }
        queueLock.withLock {
            var next = hydrated()
            next.insert(contentsOf: requests, at: 0) // deliberately no eviction — see evictIfAtCapacity
            queue = next
        }
        schedulePersist(persist)
    }

    /// Atomically snapshots and clears the pending queue, returning the drained requests.
    /// Snapshot + clear happen under a single `queueLock` acquisition so a concurrent `enqueue`
    /// cannot interleave between read and clear. Parity with the flush loop's former
    /// `requestsInFlight.append(contentsOf: queue); queue.removeAll()`.
    public func drainAll(persist: PersistPolicy = .debounced) -> [KlaviyoRequest] {
        let drained = queueLock.withLock { () -> [KlaviyoRequest] in
            let drainedRequests = hydrated()
            queue = []
            return drainedRequests
        }
        schedulePersist(persist)
        return drained
    }

    /// Merges an authoritative legacy backlog into the queue (migration only): prepends `requests`
    /// — the older, pre-upgrade backlog — ahead of whatever is already queued, skipping any id
    /// already present so a re-run can't duplicate. Prepend-not-replace is deliberate: a request
    /// that raced into the queue during the init window (MAGE-952) must survive migration rather
    /// than be wiped by a wholesale overwrite. Writes disk-first and throws on failure, since a
    /// read-back can't tell "persisted empty" from "load failed" (`hydrated()` folds both into
    /// `[]`); a failed restore leaves memory untouched so migration retries. Only supersedes a
    /// pending debounce after its own write succeeds, so a failed `restore` can't cancel a
    /// concurrent `enqueue`'s pending flush.
    ///
    /// Holds `queueLock` across the read+write+assignment (unlike `persistCurrent`), so a concurrent
    /// `enqueue` either fully precedes or fully follows `restore` rather than landing mid-merge,
    /// where it could be silently lost. `restore` runs once per app lifetime (migration-only), so
    /// this brief exception to "never hold queueLock across disk I/O" isn't a hot-path concern.
    package func restore(_ requests: [KlaviyoRequest]) throws {
        try persistLock.withLock {
            try queueLock.withLock {
                let current = hydrated()
                let existingIds = Set(current.map(\.id))
                let merged = requests.filter { !existingIds.contains($0.id) } + current
                try diskIO.save(merged)
                queue = merged
            }
            pendingDebounceToken = 0 // supersede any pending debounce; its callback will no-op
        }
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

    /// Flushes inline (`.synchronous`) or coalesces to one debounced flush per window (`.debounced`):
    /// only the first mutation in a window schedules a callback, later ones piggyback on its token,
    /// and a synchronous persist clears the token so its still-scheduled callback no-ops. Coalescing
    /// is purely an optimization — see `persistCurrent` for why a superseded fire is always safe.
    private func schedulePersist(_ policy: PersistPolicy) {
        switch policy {
        case .synchronous:
            // supersede any pending debounce; its callback will no-op
            persistLock.withLock { pendingDebounceToken = 0 }
            persistCurrent()
        case .debounced:
            let token: Int? = persistLock.withLock {
                guard pendingDebounceToken == 0 else { return nil } // coalesce onto the pending window
                debounceSeq &+= 1
                pendingDebounceToken = debounceSeq
                return debounceSeq
            }
            guard let token else { return }
            scheduler.schedule(Self.debounceInterval) { [weak self] in
                guard let self else { return }
                let isCurrent = self.persistLock.withLock { () -> Bool in
                    let current = self.pendingDebounceToken == token
                    if current { self.pendingDebounceToken = 0 }
                    return current
                }
                guard isCurrent else { return } // superseded → coalesced away
                self.persistCurrent()
            }
        }
    }

    /// Snapshots the *current* queue at write time (not at schedule time) and writes it under
    /// `persistLock`. Serialized writes of the latest memory mean disk always converges to the newest
    /// state, so a superseded debounce fire can never persist stale data. `queueLock` is held only for
    /// the snapshot and released before the disk write, so I/O never blocks queue ops.
    private func persistCurrent() {
        persistLock.withLock {
            let snapshot = queueLock.withLock { queue ?? [] }
            do {
                try diskIO.save(snapshot)
            } catch {
                emitWarning("QueueStore: failed to persist queue (\(error))")
            }
        }
    }

    // MARK: Reads

    public var requests: [KlaviyoRequest] {
        queueLock.withLock { hydrated() }
    }

    public var count: Int {
        queueLock.withLock { hydrated().count }
    }

    /// Loads from disk on first access; memory is authoritative thereafter. Call under `queueLock`.
    private func hydrated() -> [KlaviyoRequest] {
        if let queue { return queue }
        let loaded: [KlaviyoRequest]
        do {
            loaded = try diskIO.load()
        } catch {
            // A load failure is distinct from a legitimately empty/absent queue (the production
            // loader returns `[]` for an absent file without throwing). We fall back to empty so the
            // store stays usable, but the next persist then overwrites the on-disk file — which
            // self-heals a corrupt file yet, in the rare case of a transiently-unreadable *valid*
            // file, discards its backlog. Surface it so that loss is observable rather than silent.
            // (Distinguishing corrupt-vs-transient to preserve the latter is a follow-up.)
            emitWarning("QueueStore: failed to load persisted queue (\(error)); starting from empty")
            loaded = []
        }
        queue = loaded
        return loaded
    }
}

extension QueueStore {
    private static let registryLock = UnfairLock()
    private static var registry: [String: QueueStore] = [:]

    /// Resolves the current apiKey from `SDKConfigStore` and returns the (cached) store for it,
    /// or `nil` if no apiKey is set yet (buffering pre-apiKey events is handled elsewhere).
    public static func current() -> QueueStore? {
        SDKConfigStore.shared.current.apiKey.map(store(for:))
    }

    /// Returns the (cached) store for a specific apiKey, creating it on first use. Callers that
    /// have already captured an apiKey use this instead of ``current()`` so queue resolution can't
    /// race a concurrent `SDKConfigStore` change — a request built for one key always lands in that
    /// key's queue, never another key's or dropped.
    public static func store(for apiKey: String) -> QueueStore {
        registryLock.withLock {
            if let existing = registry[apiKey] { return existing }
            let store = QueueStore(apiKey: apiKey)
            registry[apiKey] = store
            return store
        }
    }

    /// Test-support: injects a pre-built store for an apiKey so reducer tests can back the queue
    /// with an in-memory spy instead of the production disk-backed store.
    package static func register(_ store: QueueStore, for apiKey: String) {
        registryLock.withLock { registry[apiKey] = store }
    }

    /// Test-support: clears the per-apiKey instance cache.
    package static func resetRegistry() {
        registryLock.withLock { registry.removeAll() }
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
