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
    func stream() -> AsyncStream<ProfileData>
}

/// Write access to profile identity. Intended for `KlaviyoSwift` only.
public protocol IdentityWriting {
    /// Wholesale replacement: overwrites the entire profile with a value you already hold in full.
    func update(_ identity: ProfileData)

    func updatePushToken(_ token: PushTokenData?)

    /// Partial edit: changes fields relative to whatever is currently stored. `transform` receives the
    /// current profile, and the read-modify-persist-emit happens as one serialized write, so a
    /// concurrent writer cannot clobber the edit (no TOCTOU). Prefer this over `current` + `update`
    /// for any field-level change (clear email, set phone, etc.). `transform` must be pure and must
    /// not call back into the store (re-enters the non-recursive write lock).
    func mutate(_ transform: (inout ProfileData) -> Void)

    /// Returns a fresh `anonymousId`. Pure — mutates no store state and neither persists nor emits;
    @discardableResult
    func mintNewAnonymousId() -> String
}

public final class IdentityStore: IdentityReading, IdentityWriting {
    public static let shared = IdentityStore()

    // TWO LOCKS (mirrors `QueueStore`'s `persistLock`/`queueLock` split):
    //
    // `writeLock` serializes an entire write — persist THEN emit — end to end, so two concurrent
    // writers can never persist in one order but emit in another (which would leave disk and the
    // last-emitted value diverged). Only writers (`update`/`updatePushToken`/`mutate`/`reset`) take it;
    // readers, subscribers, and hydration never do. Holding it across `subject.send` is therefore safe
    // against a subscriber that reads a `lock`-guarded accessor during delivery — that subscriber takes
    // `lock`, not `writeLock`.
    //
    // `lock` (non-recursive `UnfairLock`) guards `hydrated`, `pushTokenValue`, and disk I/O for short
    // critical sections. INVARIANT: never hold `lock` across `subject.send` — Combine delivers
    // synchronously, so a subscriber reading a `lock`-guarded accessor (e.g. `pushToken`) during
    // delivery would deadlock. Always mutate/persist under `lock`, release it, then emit.
    //
    // LOCK ORDERING: when both are held, `writeLock` is always the outer lock and `lock` the inner
    // one; never the reverse. Writers take `writeLock` then briefly `lock`; hydration/reads take `lock`
    // alone. Preserve this order to stay deadlock-free.
    //
    // `subject` (CurrentValueSubject) is internally synchronized, so `.value` reads and `.send`
    // need no external lock. Hydration may assign `subject.value` under `lock` only because a fresh
    // store has no subscribers yet.
    private let subject: CurrentValueSubject<ProfileData, Never>
    private let writeLock = UnfairLock()
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

    /// Wholesale replacement — see `IdentityWriting.update`. For a field-level edit derived from the
    /// current profile, use `mutate` instead (a `current` + `update` is a TOCTOU under concurrent
    /// writers).
    public func update(_ identity: ProfileData) {
        hydrateIfNeeded()
        writeLock.withLock {
            lock.withLock { persistLocked(profile: identity) }
            // Emit OUTSIDE `lock` (INVARIANT) but INSIDE `writeLock` so persist+emit stay one
            // serialized unit — no second writer can interleave and reorder disk vs last-emit.
            subject.send(identity)
        }
    }

    /// Partial, atomic edit — see `IdentityWriting.mutate`. `transform` sees the current identity, its
    /// edits are persisted, and the result is emitted, all under `writeLock`, so a concurrent writer
    /// cannot clobber the read-modify-write. `transform` must be pure and must not call back into the
    /// store (re-enters the non-recursive `writeLock`).
    public func mutate(_ transform: (inout ProfileData) -> Void) {
        hydrateIfNeeded()
        writeLock.withLock {
            let updated: ProfileData = lock.withLock {
                var profile = subject.value
                transform(&profile)
                persistLocked(profile: profile)
                return profile
            }
            subject.send(updated)
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
                persistLocked(profile: subject.value)
            }
        }
    }

    /// Clears persisted state, in-memory cache, and re-arms hydration (test isolation only).
    /// A subsequent read re-hydrates and re-mints a fresh `anonymousId`.
    package func reset() {
        writeLock.withLock {
            lock.withLock {
                hydrated = false
                pushTokenValue = nil
            }
            removePersisted(fileName: StoreFile.identity)
            subject.send(ProfileData())
        }
    }
}
