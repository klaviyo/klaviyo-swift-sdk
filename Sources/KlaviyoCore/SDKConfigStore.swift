//
//  SDKConfigStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine
import Foundation

/// SDK-wide configuration
public struct KlaviyoConfig: Equatable {
    public var apiKey: String?

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }
}

/// Read-only view of SDK configuration
public protocol ConfigReading {
    var current: KlaviyoConfig { get }
    var publisher: AnyPublisher<KlaviyoConfig, Never> { get }
    func stream() -> AsyncStream<KlaviyoConfig>
}

/// Write access to SDK configuration. Intended for `KlaviyoSwift` only.
public protocol ConfigWriting {
    func update(_ config: KlaviyoConfig)
}

public final class SDKConfigStore: ConfigReading, ConfigWriting {
    public static let shared = SDKConfigStore()

    // INVARIANT: never hold `lock` across `subject.send`. `lock` is a non-recursive `UnfairLock`;
    // Combine delivers synchronously, so a subscriber that reads a lock-guarded accessor (e.g.
    // `current`, via `hydrateIfNeeded`) during delivery would deadlock. Always mutate under the lock,
    // then emit outside it.
    //
    // SINGLE WRITER: all writes (`update`) come from the TCA reducer's write-through defer, which runs
    // serially, so persist-then-emit is never interleaved by a second writer. The lock therefore
    // guards reads (accessors, publisher/stream delivery on arbitrary threads) racing a write — not
    // writer-vs-writer.
    //
    // `subject` (CurrentValueSubject) is internally synchronized, so `.value` reads and `.send`
    // need no external lock. `lock` guards only `hydrated` and disk I/O. Hydration may assign
    // `subject.value` under the lock only because a fresh store has no subscribers yet.
    private let subject: CurrentValueSubject<KlaviyoConfig, Never>
    private let lock = UnfairLock()
    private var hydrated = false

    /// Canonical home for new SDK support files, matching `QueueStore`/`UnattributedBuffer`.
    /// Resolved per-access so tests can swap the environment's file client.
    private var storeDirectory: URL { environment.fileClient.applicationSupportDirectory() }

    init(initialConfig: KlaviyoConfig = KlaviyoConfig()) {
        subject = CurrentValueSubject(initialConfig)
    }

    private func hydrateIfNeeded() {
        lock.withLock {
            guard !hydrated else { return }
            hydrated = true
            if let persisted = loadPersisted(
                PersistedConfig.self, fileName: StoreFile.config, directory: storeDirectory
            ) {
                // Assign directly rather than `send` — no subscribers exist on a fresh store.
                subject.value = KlaviyoConfig(apiKey: persisted.apiKey)
            }
        }
    }

    public var current: KlaviyoConfig {
        hydrateIfNeeded()
        return subject.value
    }

    public var publisher: AnyPublisher<KlaviyoConfig, Never> {
        hydrateIfNeeded()
        return subject.eraseToAnyPublisher()
    }

    public func stream() -> AsyncStream<KlaviyoConfig> {
        hydrateIfNeeded()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let cancellable = subject.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    public func update(_ config: KlaviyoConfig) {
        hydrateIfNeeded()
        // Persist under the lock so concurrent `update` calls can't interleave file writes.
        // The `config` param is written directly, so there is no stale-snapshot risk.
        lock.withLock {
            savePersisted(
                PersistedConfig(version: PersistedConfig.currentVersion, apiKey: config.apiKey),
                fileName: StoreFile.config, directory: storeDirectory
            )
        }
        // Emit OUTSIDE the lock — Combine delivers synchronously to subscribers.
        subject.send(config)
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    package func reset() {
        lock.withLock { hydrated = false }
        removePersisted(fileName: StoreFile.config, directory: storeDirectory)
        subject.send(KlaviyoConfig())
    }
}
