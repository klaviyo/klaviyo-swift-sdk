//
//  UnattributedBuffer.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/26.
//

import Foundation

/// One request-generating call captured before an apiKey was known. Stored apiKey-free
/// (the apiKey is stamped into the endpoint at drain). Named to echo `UnattributedBuffer`.
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

    private let lock = UnfairLock()
    private var hydrated = false
    private var requests: [UnattributedRequest] = []

    /// Canonical home for new SDK support files, matching `QueueStore` (the store this buffer
    /// drains into). Resolved per-access so tests can swap the environment's file client.
    private var storeDirectory: URL { environment.fileClient.applicationSupportDirectory() }

    /// Loads from disk on first access; memory is authoritative thereafter. Call under `lock`.
    private func hydrateIfNeeded() {
        guard !hydrated else { return }
        hydrated = true
        if let persisted = loadPersisted(
            PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed,
            directory: storeDirectory
        ) {
            requests = persisted.requests
        }
    }

    /// Writes the current in-memory buffer through to disk (or removes the file when empty).
    /// Call under `lock`.
    private func persist() {
        if requests.isEmpty {
            removePersisted(fileName: StoreFile.unattributed, directory: storeDirectory)
        } else {
            savePersisted(
                PersistedUnattributedBuffer(requests: requests),
                fileName: StoreFile.unattributed, directory: storeDirectory
            )
        }
    }

    func append(_ request: UnattributedRequest) {
        lock.withLock {
            hydrateIfNeeded()
            if requests.count >= Self.maxBufferSize {
                requests.removeFirst()
            }
            requests.append(request)
            persist()
        }
    }

    func snapshot() -> [UnattributedRequest] {
        lock.withLock {
            hydrateIfNeeded()
            return requests
        }
    }

    /// Removes the first `count` requests — the FIFO prefix a drain has already enqueued — and
    /// persists the remainder, all under one lock. Unlike `clear()`, requests appended
    /// concurrently during a drain sit past the prefix and survive, preserving at-least-once.
    func removeDrained(_ count: Int) {
        lock.withLock {
            hydrateIfNeeded()
            let removalCount = min(count, requests.count)
            guard removalCount > 0 else { return }
            requests.removeFirst(removalCount)
            persist()
        }
    }

    func clear() {
        lock.withLock {
            requests = []
            hydrated = true
            removePersisted(fileName: StoreFile.unattributed, directory: storeDirectory)
        }
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    package func reset() {
        lock.withLock {
            hydrated = false
            requests = []
            removePersisted(fileName: StoreFile.unattributed, directory: storeDirectory)
        }
    }
}
