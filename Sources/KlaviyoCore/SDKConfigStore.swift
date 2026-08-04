//
//  SDKConfigStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine
import os

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

    // `CurrentValueSubject` is internally synchronized, so reads and writes are thread-safe.
    // The `lock` guards only the `hydrated` flag and disk I/O — it is NEVER held across
    // `subject.send(_:)`, since Combine delivers synchronously and a subscriber reading
    // `current` under the same lock would deadlock.
    private let subject: CurrentValueSubject<KlaviyoConfig, Never>
    private var lock = os_unfair_lock_s()
    private var hydrated = false

    init(initialConfig: KlaviyoConfig = KlaviyoConfig()) {
        subject = CurrentValueSubject(initialConfig)
    }

    private func hydrateIfNeeded() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard !hydrated else { return }
        hydrated = true
        if let persisted = loadPersisted(PersistedConfig.self, fileName: StoreFile.config) {
            // Use `subject.value =` (not `.send`) — a fresh store has no subscribers yet,
            // and direct assignment avoids emitting under the lock.
            subject.value = KlaviyoConfig(apiKey: persisted.apiKey)
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
        savePersisted(
            PersistedConfig(version: PersistedConfig.currentVersion, apiKey: config.apiKey),
            fileName: StoreFile.config)
        // Emit OUTSIDE the lock — Combine delivers synchronously to subscribers.
        subject.send(config)
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    package func reset() {
        os_unfair_lock_lock(&lock)
        hydrated = false
        os_unfair_lock_unlock(&lock)
        let fileURL = environment.fileClient.libraryDirectory()
            .appendingPathComponent(StoreFile.config, isDirectory: false)
        try? environment.fileClient.removeItem(fileURL.path)
        subject.send(KlaviyoConfig())
    }
}
