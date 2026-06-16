//
//  IdentityStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine

/// Read-only view of profile identity. Consumers depend on this rather than the
/// concrete store so the underlying implementation can change (e.g. become an actor).
public protocol IdentityReading {
    var current: ProfileData { get }
    var publisher: AnyPublisher<ProfileData, Never> { get }
    func stream() -> AsyncStream<ProfileData>
}

/// Write access to profile identity. Intended for `KlaviyoSwift` only.
public protocol IdentityWriting {
    func update(_ identity: ProfileData)
}

public final class IdentityStore: IdentityReading, IdentityWriting {
    public static let shared = IdentityStore()

    // `CurrentValueSubject` is internally synchronized, so reads and writes are thread-safe
    // without an external lock. We deliberately avoid wrapping `send` in a lock/queue: Combine
    // delivers to subscribers synchronously during `send`, so an external lock held across the
    // emission would deadlock any subscriber that reads `current` in response.
    private let subject: CurrentValueSubject<ProfileData, Never>

    init(initialIdentity: ProfileData = ProfileData()) {
        subject = CurrentValueSubject(initialIdentity)
    }

    public var current: ProfileData {
        subject.value
    }

    public var publisher: AnyPublisher<ProfileData, Never> {
        subject.eraseToAnyPublisher()
    }

    public func stream() -> AsyncStream<ProfileData> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let cancellable = subject.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    public func update(_ identity: ProfileData) {
        subject.send(identity)
    }
}
