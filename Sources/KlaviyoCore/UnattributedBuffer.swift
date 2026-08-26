//
//  UnattributedBuffer.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/26.
//

import Foundation

/// One request-generating call captured before an apiKey was known. Stored apiKey-free
/// (the apiKey is stamped into the endpoint at drain).
enum UnattributedRequest: Codable, Equatable {
    case event(CreateEventPayload, RequestPriority)
    case aggregateEvent(Data)
    case profile(CreateProfilePayload)
    case pushToken(PushTokenPayload)
}

/// Versioned on-disk shape for the buffer file (`klaviyo-unattributed.json`).
struct PersistedUnattributedBuffer: Codable, Equatable {
    static let currentVersion = 1
    var version: Int
    var requests: [UnattributedRequest]

    init(version: Int = currentVersion, requests: [UnattributedRequest] = []) {
        self.version = version
        self.requests = requests
    }
}

/// Durable, device-scoped sink for request-generating calls made before an apiKey is known.
/// Ungated: usable without `initialize()`. Not observed — no Combine subject. All mutations
/// write through synchronously; `RequestEnqueuer` owns the drain-into-QueueStore orchestration.
final class UnattributedBuffer {
    static let shared = UnattributedBuffer()
    static let maxBufferSize = 200

    /// A buffered request tagged with a process-local, monotonically increasing sequence. The
    /// sequence — not the array index — identifies an item across cap-eviction and appends, so a
    /// drain can trim exactly what it snapshotted. Sequences are in-memory only (reassigned on
    /// hydrate); durability comes from the persisted `UnattributedRequest`s alone.
    private struct Entry {
        let sequence: UInt64
        let request: UnattributedRequest
    }

    private let lock = UnfairLock()
    private var hydrated = false
    private var entries: [Entry] = []
    /// Starts at 1 so the `0` cursor `drainSnapshot()` returns for an empty buffer can never
    /// match a real entry's sequence.
    private var nextSequence: UInt64 = 1

    /// Loads from disk on first access; memory is authoritative thereafter. Call under `lock`.
    private func hydrateIfNeeded() {
        guard !hydrated else { return }
        hydrated = true
        if let persisted = loadPersisted(
            PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed
        ) {
            entries = persisted.requests.map { assignSequence($0) }
        }
    }

    /// Wraps a request in an `Entry` with the next sequence. Call under `lock`.
    private func assignSequence(_ request: UnattributedRequest) -> Entry {
        defer { nextSequence += 1 }
        return Entry(sequence: nextSequence, request: request)
    }

    /// Writes the current in-memory buffer through to disk (or removes the file when empty).
    /// Call under `lock`.
    private func persist() {
        if entries.isEmpty {
            removePersisted(fileName: StoreFile.unattributed)
        } else {
            savePersisted(
                PersistedUnattributedBuffer(requests: entries.map(\.request)),
                fileName: StoreFile.unattributed
            )
        }
    }

    /// A push-token registration is a snapshot of "the current token state" — a repeated pre-init
    /// fire (e.g. multiple automatic APNs callbacks before `initialize()`) makes any earlier buffered
    /// `.pushToken` redundant, so it's dropped in favor of the newest one rather than both being
    /// drained and sent. Not provenance-aware (manual vs. automatic) — coalescing applies regardless
    /// of which caller produced the request, since both build the same idempotent payload shape.
    func append(_ request: UnattributedRequest) {
        lock.withLock {
            hydrateIfNeeded()
            if case .pushToken = request {
                entries.removeAll {
                    if case .pushToken = $0.request { return true }
                    return false
                }
            }
            if entries.count >= Self.maxBufferSize {
                entries.removeFirst()
            }
            entries.append(assignSequence(request))
            persist()
        }
    }

    func snapshot() -> [UnattributedRequest] {
        lock.withLock {
            hydrateIfNeeded()
            return entries.map(\.request)
        }
    }

    /// Atomic drain snapshot: the buffered requests plus a `cursor` identifying them. Pass the
    /// cursor back to `removeDrained(throughCursor:)` after enqueuing to remove exactly those
    /// items — even if cap-eviction or a concurrent append reshaped the buffer in between.
    func drainSnapshot() -> (requests: [UnattributedRequest], cursor: UInt64) {
        lock.withLock {
            hydrateIfNeeded()
            return (entries.map(\.request), entries.last?.sequence ?? 0)
        }
    }

    /// Removes every buffered request whose sequence is `<= cursor` — the items a drain has
    /// already enqueued — and persists the remainder, all under one lock. Front-eviction only
    /// drops even-lower sequences and appends only mint higher ones, so an item appended
    /// concurrently during a drain survives instead of being swept up, preserving at-least-once.
    func removeDrained(throughCursor cursor: UInt64) {
        lock.withLock {
            hydrateIfNeeded()
            let before = entries.count
            entries.removeAll { $0.sequence <= cursor }
            guard entries.count != before else { return }
            persist()
        }
    }

    func clear() {
        lock.withLock {
            entries = []
            hydrated = true
            removePersisted(fileName: StoreFile.unattributed)
        }
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    package func reset() {
        lock.withLock {
            hydrated = false
            entries = []
            nextSequence = 1
            removePersisted(fileName: StoreFile.unattributed)
        }
    }
}
