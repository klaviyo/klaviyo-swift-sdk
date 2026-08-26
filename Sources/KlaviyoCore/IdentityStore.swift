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
    var pushToken: PushTokenData? { get }
    var publisher: AnyPublisher<ProfileData, Never> { get }
    func stream() -> AsyncStream<ProfileData>
}

/// Write access to profile identity. Intended for `KlaviyoSwift` only.
public protocol IdentityWriting {
    func update(_ identity: ProfileData)
    func updatePushToken(_ token: PushTokenData?)

    /// Returns a fresh `anonymousId`. Pure — mutates no store state and neither persists nor emits;
    @discardableResult
    func mintNewAnonymousId() -> String
}

public final class IdentityStore: IdentityReading, IdentityWriting {
    public static let shared = IdentityStore()

    // INVARIANT: never hold `lock` across `subject.send`. `lock` is a non-recursive `UnfairLock`;
    // Combine delivers synchronously, so a subscriber that reads a lock-guarded accessor (e.g.
    // `pushToken`) during delivery would deadlock. Always mutate under the lock, then emit outside it.
    //
    // SINGLE WRITER: all writes (`update`/`updatePushToken`) come from the TCA reducer's write-through
    // defer, which runs serially, so persist-then-emit is never interleaved by a second writer. The
    // lock therefore guards reads (accessors, publisher/stream delivery on arbitrary threads) racing a
    // write — not writer-vs-writer. If a concurrent writer is ever introduced, persist and emit could
    // reorder across threads; revisit this the way `QueueStore.persistCurrent` handles it.
    //
    // `subject` (CurrentValueSubject) is internally synchronized, so `.value` reads and `.send`
    // need no external lock. `lock` guards only `hydrated`, `pushTokenValue`, and disk I/O. Hydration
    // may assign `subject.value` under the lock only because a fresh store has no subscribers yet.
    private let subject: CurrentValueSubject<ProfileData, Never>
    private let lock = UnfairLock()
    private var hydrated = false
    private var pushTokenValue: PushTokenData?

    init(initialIdentity: ProfileData = ProfileData()) {
        subject = CurrentValueSubject(initialIdentity)
    }

    /// Hydrate from disk once; lazily mint + persist an `anonymousId` if none is on disk.
    private func hydrateIfNeeded() {
        lock.withLock {
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
    }

    /// Writes the combined DTO (profile + current push token).
    private func persistLocked(profile: ProfileData) {
        savePersisted(
            PersistedIdentity(
                version: PersistedIdentity.currentVersion,
                profile: profile,
                pushToken: pushTokenValue
            ),
            fileName: StoreFile.identity
        )
    }

    public var current: ProfileData {
        hydrateIfNeeded()
        return subject.value
    }

    public var pushToken: PushTokenData? {
        hydrateIfNeeded()
        return lock.withLock { pushTokenValue }
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
        lock.withLock { persistLocked(profile: identity) }
        // Emit OUTSIDE the lock — Combine delivers synchronously to subscribers.
        subject.send(identity)
    }

    @discardableResult
    public func mintNewAnonymousId() -> String {
        environment.uuid().uuidString
    }

    public func updatePushToken(_ token: PushTokenData?) {
        hydrateIfNeeded()
        lock.withLock {
            pushTokenValue = token
            // Persist the combined DTO; the profile side is unchanged, so no emission.
            persistLocked(profile: subject.value)
        }
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    /// A subsequent read re-hydrates and re-mints a fresh `anonymousId`.
    package func reset() {
        lock.withLock {
            hydrated = false
            pushTokenValue = nil
        }
        removePersisted(fileName: StoreFile.identity)
        subject.send(ProfileData())
    }
}
