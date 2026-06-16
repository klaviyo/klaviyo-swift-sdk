//
//  SDKConfigStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine
import Foundation

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

    /// Serializes reads and writes to the backing subject.
    private let queue = DispatchQueue(label: "com.klaviyo.sdk-config-store")
    private let apiKeySubject: CurrentValueSubject<String?, Never>

    init(initialAPIKey: String? = nil) {
        apiKeySubject = CurrentValueSubject(initialAPIKey)
    }

    public var apiKey: String? {
        queue.sync { apiKeySubject.value }
    }

    public var apiKeyPublisher: AnyPublisher<String?, Never> {
        apiKeySubject.eraseToAnyPublisher()
    }

    public func updateAPIKey(_ apiKey: String?) {
        queue.sync { apiKeySubject.send(apiKey) }
    }
}
