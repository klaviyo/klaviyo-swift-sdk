//
//  SDKConfigStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine

/// Read-only view of SDK configuration. Consumers depend on this rather than the
/// concrete store so the underlying implementation can change (e.g. become an actor).
public protocol ConfigReading {
    var apiKey: String? { get }
    var apiKeyPublisher: AnyPublisher<String?, Never> { get }
}

/// Write access to SDK configuration. Intended for `KlaviyoSwift` only.
public protocol ConfigWriting {
    func updateAPIKey(_ apiKey: String?)
}

public final class SDKConfigStore: ConfigReading, ConfigWriting {
    public static let shared = SDKConfigStore()

    // `CurrentValueSubject` is internally synchronized, so reads and writes are thread-safe
    // without an external lock. We deliberately avoid wrapping `send` in a lock/queue: Combine
    // delivers to subscribers synchronously during `send`, so an external lock held across the
    // emission would deadlock any subscriber that reads `apiKey` in response.
    private let apiKeySubject: CurrentValueSubject<String?, Never>

    init(initialAPIKey: String? = nil) {
        apiKeySubject = CurrentValueSubject(initialAPIKey)
    }

    public var apiKey: String? {
        apiKeySubject.value
    }

    public var apiKeyPublisher: AnyPublisher<String?, Never> {
        apiKeySubject.eraseToAnyPublisher()
    }

    public func updateAPIKey(_ apiKey: String?) {
        apiKeySubject.send(apiKey)
    }
}
