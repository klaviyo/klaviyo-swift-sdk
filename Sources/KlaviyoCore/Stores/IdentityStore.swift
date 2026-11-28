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
    var pushToken: PushTokenData? { get }
    var publisher: AnyPublisher<ProfileData, Never> { get }
    var tokenPublisher: AnyPublisher<PushTokenData?, Never> { get }
    func stream() -> AsyncStream<ProfileData>
}

extension IdentityReading {
    public var tokenPublisher: AnyPublisher<PushTokenData?, Never> { Just(pushToken).eraseToAnyPublisher() }
}

/// Write access to profile identity. Intended for `KlaviyoSwift` only.
public protocol IdentityWriting {
    /// Wholesale replacement: overwrites the entire profile with a value you already hold in full.
    func update(_ identity: ProfileData)

    func updatePushToken(_ token: PushTokenData?)

    /// Partial edit: `transform` receives the current profile; the read-modify-persist-emit is one
    /// serialized write, so a concurrent writer cannot clobber it (no TOCTOU). Prefer over
    /// `current` + `update` for any field-level change. `transform` must be pure and must not call
    /// back into the store (re-enters the non-recursive write lock).
    func mutate(_ transform: (inout ProfileData) -> Void)

    /// Returns a fresh `anonymousId`. Pure — mutates no store state and neither persists nor emits;
    @discardableResult
    func mintNewAnonymousId() -> String
}

/// A profile paired with the sequence number of the write that produced it.
package struct VersionedProfile: Equatable {
    package let profile: ProfileData
    /// Starts at 0 for a never-written store and strictly increases with every profile write.
    package let sequence: UInt64
}

/// ``IdentityReading`` that also exposes each value's sequence number, so a consumer can tell a
/// stale read from a newer one.
package protocol VersionedIdentityReading: IdentityReading {
    var versioned: VersionedProfile { get }
    var versionedPublisher: AnyPublisher<VersionedProfile, Never> { get }
}

/// The persisted profile identity store.
///
/// Every profile value carries a sequence number (``VersionedProfile``) that starts at 0 for a
/// never-written store and strictly increases with every profile write: `update`, `mutate` and
/// `reset` each advance it and emit the new value; `updatePushToken` does not advance it and does
/// not emit on the profile subject. The sequence never restarts, including across `reset()` and
/// rehydration — hydration assigns the hydrated profile while preserving the current sequence.
/// Sequence order equals emission order because persist+emit are one serialized unit under
/// `writeLock`.
public final class IdentityStore: IdentityReading, IdentityWriting, VersionedIdentityReading {
    public static let shared = IdentityStore()

    // TWO LOCKS (mirrors `QueueStore`'s `persistLock`/`queueLock` split):
    //
    // `writeLock` serializes a whole write (persist THEN emit) so two writers can't persist in one
    // order but emit in another, diverging disk from the last-emitted value. Only writers take it.
    //
    // `lock` (non-recursive `UnfairLock`) guards `hydrated`, `pushTokenValue`, and disk I/O for short
    // critical sections. INVARIANT: never hold `lock` across `subject.send` — Combine delivers
    // synchronously, so a subscriber reading a `lock`-guarded accessor (e.g. `pushToken`) during
    // delivery would deadlock. Mutate/persist under `lock`, release, then emit.
    //
    // LOCK ORDERING: `writeLock` is always outer, `lock` inner — never the reverse.
    //
    // `subject` (CurrentValueSubject) is internally synchronized. Hydration may assign `subject.value`
    // under `lock` only because a fresh store has no subscribers yet.
    // `tokenSubject` follows the same invariant: seeded under `lock` on a fresh store only; emitted
    // outside `lock` (inside `writeLock`) in all write paths.
    private let subject: CurrentValueSubject<VersionedProfile, Never>
    private let tokenSubject: CurrentValueSubject<PushTokenData?, Never>
    private let writeLock = UnfairLock()
    private let lock = UnfairLock()
    private var hydrated = false
    private var pushTokenValue: PushTokenData?

    /// - Parameter initialIdentity: when non-nil, seeds the store and skips disk hydration
    ///   (test seam: a seeded store must not be overwritten by the persisted/minted profile).
    init(initialIdentity: ProfileData? = nil) {
        subject = CurrentValueSubject(
            VersionedProfile(profile: initialIdentity ?? ProfileData(), sequence: 0)
        )
        tokenSubject = CurrentValueSubject(nil)
        hydrated = initialIdentity != nil
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
            // Preserve the current sequence: hydration is not a write and the sequence never
            // restarts, including across `reset()` re-arming hydration.
            subject.value = VersionedProfile(profile: profile, sequence: subject.value.sequence)
            // Seed token subject; safe to assign directly (no subscribers on a fresh store).
            tokenSubject.value = pushTokenValue
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
        return subject.value.profile
    }

    public var pushToken: PushTokenData? {
        hydrateIfNeeded()
        return lock.withLock { pushTokenValue }
    }

    public var publisher: AnyPublisher<ProfileData, Never> {
        hydrateIfNeeded()
        return subject.map(\.profile).eraseToAnyPublisher()
    }

    public var tokenPublisher: AnyPublisher<PushTokenData?, Never> {
        hydrateIfNeeded()
        return tokenSubject.eraseToAnyPublisher()
    }

    package var versioned: VersionedProfile {
        hydrateIfNeeded()
        return subject.value
    }

    package var versionedPublisher: AnyPublisher<VersionedProfile, Never> {
        hydrateIfNeeded()
        return subject.eraseToAnyPublisher()
    }

    public func stream() -> AsyncStream<ProfileData> {
        hydrateIfNeeded()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let cancellable = subject.sink { value in
                continuation.yield(value.profile)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    /// Wholesale replacement — see `IdentityWriting.update`. For a field-level edit derived from the
    /// current profile, use `mutate` instead (a `current` + `update` is a TOCTOU under concurrent
    /// writers).
    public func update(_ identity: ProfileData) {
        hydrateIfNeeded()
        writeLock.withLock {
            lock.withLock { persistLocked(profile: identity) }
            // Emit outside `lock` (INVARIANT), inside `writeLock` so persist+emit stay one unit.
            subject.send(VersionedProfile(profile: identity, sequence: subject.value.sequence + 1))
        }
    }

    /// Partial, atomic edit — see `IdentityWriting.mutate`. Read-modify-persist-emit runs under
    /// `writeLock` so a concurrent writer can't clobber it. `transform` must be pure and must not
    /// call back into the store (re-enters the non-recursive `writeLock`).
    public func mutate(_ transform: (inout ProfileData) -> Void) {
        hydrateIfNeeded()
        writeLock.withLock {
            let updated: ProfileData = lock.withLock {
                var profile = subject.value.profile
                transform(&profile)
                persistLocked(profile: profile)
                return profile
            }
            subject.send(VersionedProfile(profile: updated, sequence: subject.value.sequence + 1))
        }
    }

    @discardableResult
    public func mintNewAnonymousId() -> String {
        environment.uuid().uuidString
    }

    public func updatePushToken(_ token: PushTokenData?) {
        hydrateIfNeeded()
        writeLock.withLock {
            lock.withLock {
                pushTokenValue = token
                // Persist the combined DTO; the profile side is unchanged, so no emission.
                persistLocked(profile: subject.value.profile)
            }
            // Emit outside `lock` (INVARIANT), inside `writeLock` so persist+emit stay one unit.
            tokenSubject.send(token)
        }
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    /// A subsequent read re-hydrates and re-mints a fresh `anonymousId`.
    package func reset() {
        writeLock.withLock {
            lock.withLock {
                hydrated = false
                pushTokenValue = nil
                // Delete under `lock` so the file removal can't interleave with a concurrent
                // hydrate/persist. Emit stays outside `lock` (INVARIANT), inside `writeLock`.
                removePersisted(fileName: StoreFile.identity)
            }
            subject.send(VersionedProfile(profile: ProfileData(), sequence: subject.value.sequence + 1))
            // Emit nil outside `lock` (INVARIANT), inside `writeLock`.
            tokenSubject.send(nil)
        }
    }
}
