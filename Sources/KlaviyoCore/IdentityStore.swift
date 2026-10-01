//
//  IdentityStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine
import Foundation

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

/// A profile paired with the sequence number of the update that produced it.
package struct VersionedProfile: Equatable {
    package let profile: ProfileData
    /// Starts at 0 for the initial identity and increases by one with every update.
    package let sequence: UInt64
}

/// ``IdentityReading`` that also exposes the sequence number of each value, so a consumer
/// can tell a stale read from a newer one.
package protocol VersionedIdentityReading: IdentityReading {
    /// The latest profile and its sequence number, read together.
    var versioned: VersionedProfile { get }
    /// Emits the current value on subscription and every update after it.
    var versionedPublisher: AnyPublisher<VersionedProfile, Never> { get }
}

/// Holds the current profile identity.
///
/// Calls to ``update(_:)`` must be serialized by the caller. The shared store is written only by
/// `SharedStoreMirror`, on the main thread. Updates are numbered in the order they are made.
public final class IdentityStore: IdentityReading, IdentityWriting, VersionedIdentityReading {
    public static let shared = IdentityStore()

    // `CurrentValueSubject` is internally synchronized; `lock` guards `sequence`.
    private let subject: CurrentValueSubject<VersionedProfile, Never>
    private let lock = NSLock()
    private var sequence: UInt64 = 0

    init(initialIdentity: ProfileData = ProfileData()) {
        subject = CurrentValueSubject(VersionedProfile(profile: initialIdentity, sequence: 0))
    }

    public var current: ProfileData {
        subject.value.profile
    }

    public var publisher: AnyPublisher<ProfileData, Never> {
        subject.map(\.profile).eraseToAnyPublisher()
    }

    package var versioned: VersionedProfile {
        subject.value
    }

    package var versionedPublisher: AnyPublisher<VersionedProfile, Never> {
        subject.eraseToAnyPublisher()
    }

    public func stream() -> AsyncStream<ProfileData> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let cancellable = subject.sink { value in
                continuation.yield(value.profile)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    public func update(_ identity: ProfileData) {
        lock.lock()
        sequence += 1
        let next = VersionedProfile(profile: identity, sequence: sequence)
        lock.unlock()
        subject.send(next)
    }

    /// Restores the store to empty identity (test-support / Core reset surface).
    package func reset() {
        update(ProfileData())
    }
}
