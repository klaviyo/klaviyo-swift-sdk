//
//  SDKConfigStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine

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

    // `CurrentValueSubject` is internally synchronized, so reads and writes are thread-safe
    // without an external lock. We deliberately avoid wrapping `send` in a lock/queue: Combine
    // delivers to subscribers synchronously during `send`, so an external lock held across the
    // emission would deadlock any subscriber that reads `current` in response.
    private let subject: CurrentValueSubject<KlaviyoConfig, Never>

    init(initialConfig: KlaviyoConfig = KlaviyoConfig()) {
        subject = CurrentValueSubject(initialConfig)
    }

    public var current: KlaviyoConfig {
        subject.value
    }

    public var publisher: AnyPublisher<KlaviyoConfig, Never> {
        subject.eraseToAnyPublisher()
    }

    public func stream() -> AsyncStream<KlaviyoConfig> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let cancellable = subject.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    public func update(_ config: KlaviyoConfig) {
        subject.send(config)
    }
}
