//
//  IdentityStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

import Combine
import os

/// Read-only view of profile identity. Consumers depend on this rather than the
/// concrete store so the underlying implementation can change (e.g. become an actor).
public protocol IdentityReading {
    var current: ProfileData { get }
    var pushToken: PushTokenData? { get }
    var publisher: AnyPublisher<ProfileData, Never> { get }
    func stream() -> AsyncStream<ProfileData>
}

/// Write access to profile identity. Intended for `KlaviyoSwift` only.
public protocol IdentityWriting {
    func update(_ identity: ProfileData)
    func updatePushToken(_ token: PushTokenData?)

    /// Mints a fresh `anonymousId`, persists it, and returns the new value. This is the ONLY
    /// public mint seam — used by `KlaviyoSwift`'s profile-reset flow, which must force a fresh
    /// anonymous id synchronously (so a cleared, formerly-identified profile becomes a distinct
    /// anonymous profile). Minting otherwise happens lazily on first hydrate.
    @discardableResult
    func mintNewAnonymousId() -> String
}

public final class IdentityStore: IdentityReading, IdentityWriting {
    public static let shared = IdentityStore()

    // `CurrentValueSubject` is internally synchronized, so reads and writes are thread-safe.
    // The `lock` guards the `hydrated` flag, the push-token field, and disk I/O — it is NEVER
    // held across `subject.send(_:)`, since Combine delivers synchronously and a subscriber
    // reading `current` under the same lock would deadlock. Hydration assigns `subject.value =`
    // (not `.send`) — a fresh store has no subscribers yet, so no emission happens under the lock.
    private let subject: CurrentValueSubject<ProfileData, Never>
    private var lock = os_unfair_lock_s()
    private var hydrated = false
    private var pushTokenValue: PushTokenData?

    init(initialIdentity: ProfileData = ProfileData()) {
        subject = CurrentValueSubject(initialIdentity)
    }

    /// Hydrate from disk once; mint + persist an `anonymousId` if none is on disk.
    /// This is the ONLY place an `anonymousId` is minted.
    private func hydrateIfNeeded() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard !hydrated else { return }
        hydrated = true

        let persisted = loadPersisted(PersistedIdentity.self, fileName: StoreFile.identity)
        var profile = persisted?.profile ?? ProfileData()
        pushTokenValue = persisted?.pushToken

        if profile.anonymousId == nil {
            profile.anonymousId = environment.uuid().uuidString
            persistLocked(profile: profile) // disk write only, no send
        }
        // Assign directly rather than `send` — no subscribers exist on a fresh store.
        subject.value = profile
    }

    /// Writes the combined DTO (profile + current push token). Caller holds `lock`.
    private func persistLocked(profile: ProfileData) {
        savePersisted(
            PersistedIdentity(
                version: PersistedIdentity.currentVersion,
                profile: profile,
                pushToken: pushTokenValue),
            fileName: StoreFile.identity)
    }

    public var current: ProfileData {
        hydrateIfNeeded()
        return subject.value
    }

    public var pushToken: PushTokenData? {
        hydrateIfNeeded()
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return pushTokenValue
    }

    public var publisher: AnyPublisher<ProfileData, Never> {
        hydrateIfNeeded()
        return subject.eraseToAnyPublisher()
    }

    public func stream() -> AsyncStream<ProfileData> {
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

    public func update(_ identity: ProfileData) {
        hydrateIfNeeded()
        os_unfair_lock_lock(&lock)
        persistLocked(profile: identity)
        os_unfair_lock_unlock(&lock)
        // Emit OUTSIDE the lock — Combine delivers synchronously to subscribers.
        subject.send(identity)
    }

    @discardableResult
    public func mintNewAnonymousId() -> String {
        hydrateIfNeeded()
        let newId = environment.uuid().uuidString
        os_unfair_lock_lock(&lock)
        var profile = subject.value
        profile.anonymousId = newId
        persistLocked(profile: profile)
        os_unfair_lock_unlock(&lock)
        // Emit OUTSIDE the lock — Combine delivers synchronously to subscribers.
        subject.send(profile)
        return newId
    }

    public func updatePushToken(_ token: PushTokenData?) {
        hydrateIfNeeded()
        os_unfair_lock_lock(&lock)
        pushTokenValue = token
        // Persist the combined DTO; the profile side is unchanged, so no emission.
        persistLocked(profile: subject.value)
        os_unfair_lock_unlock(&lock)
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    /// A subsequent read re-hydrates and re-mints a fresh `anonymousId`.
    package func reset() {
        os_unfair_lock_lock(&lock)
        hydrated = false
        pushTokenValue = nil
        os_unfair_lock_unlock(&lock)
        removePersisted(fileName: StoreFile.identity)
        subject.send(ProfileData())
    }
}
