//
//  ProfilePropertyBuffer.swift
//
//
//  Created by Isobelle Lim on 9/11/26.
//

import AnyCodable
import Foundation
import KlaviyoCore

/// KlaviyoSwift-side staging for profile properties set via `setProfileProperty`.
///
/// Properties staged here are flushed into `QueueStore` just before the `RequestQueue` actor
/// sends a batch (`willDrain`):
///
/// - **Push token present** → fold staged props into a `Profile`, build a `ProfilePayload`, then
///   enqueue a `registerPushToken` request via `RequestFactory.tokenRequest`.
/// - **No push token** → build a base `CreateProfilePayload` from identity, fold staged props in
///   via `PendingProfileFold`, then enqueue via `RequestEnqueuer.enqueueProfile(payload:)`.
///
/// Identity is always read fresh from `IdentityStore.shared` at flush time (post-init, so
/// `anonymousId` is guaranteed non-nil in practice). `flushIntoQueue` guards on `apiKey` presence
/// defensively — the actor only calls `willDrain` after initialization, so the guard should never
/// trip, but we retain it against future call-site changes.
///
/// Thread-safety: `staged` is protected by `NSLock`. `stage` may be called on any thread
/// (typically the main thread from `setProfileProperty`). `flushIntoQueue` is called from the
/// actor's executor. The dict is snapshot-and-cleared atomically at the start of `flushIntoQueue`
/// so the actor sees a consistent view even if `stage` races with the flush.
final class ProfilePropertyBuffer: @unchecked Sendable {
    static let shared = ProfilePropertyBuffer()

    private let lock = NSLock()
    private var staged: [Profile.ProfileKey: AnyEncodable] = [:]

    // MARK: - API

    /// Stages a single property key/value. Safe to call from any thread.
    func stage(_ key: Profile.ProfileKey, _ value: AnyEncodable) {
        lock.withLock { staged[key] = value }
    }

    /// Snapshot-and-clears the staged dict, folds the properties into the appropriate request, and
    /// enqueues it. No-op when the buffer is empty or when `apiKey` is not yet configured.
    func flushIntoQueue() async {
        // Snapshot-and-clear under the lock so a concurrent `stage` call cannot race.
        let snapshot = lock.withLock {
            let snap = staged
            staged = [:]
            return snap
        }

        guard !snapshot.isEmpty else { return }

        guard let apiKey = SDKConfigStore.shared.current.apiKey else {
            // Restore the snapshot so staged properties aren't dropped.
            lock.withLock { staged = snapshot.merging(staged) { _, new in new } }
            environment.emitDeveloperWarning(
                "ProfilePropertyBuffer.flushIntoQueue: apiKey not set; staged properties retained"
            )
            return
        }

        // Capture identity and push token together, up front, so the fold and the token-vs-profile
        // decision below read one consistent view rather than re-accessing the store after other work.
        let identity = IdentityStore.shared.current
        let pushTokenData = IdentityStore.shared.pushToken
        guard let anonymousId = identity.anonymousId else {
            lock.withLock { staged = snapshot.merging(staged) { _, new in new } }
            environment.emitDeveloperWarning(
                "ProfilePropertyBuffer.flushIntoQueue: missing anonymousId; staged properties retained"
            )
            return
        }

        if let tokenData = pushTokenData {
            // Push-token path: fold staged props into a Profile → ProfilePayload → tokenRequest.
            // Must NOT use RequestEnqueuer.enqueuePushToken here because it builds from flat identity
            // only and drops structured attributes (firstName, lastName, title, etc.).
            let profile = Profile.updateProfileWithProperties(
                email: identity.email,
                phoneNumber: identity.phoneNumber,
                externalId: identity.externalId,
                dict: snapshot
            )
            let profilePayload = ProfilePayload(profile, anonymousId: anonymousId)
            let request = RequestFactory.tokenRequest(
                apiKey: apiKey,
                pushToken: tokenData.pushToken,
                enablement: tokenData.pushEnablement,
                background: environment.getBackgroundSetting().rawValue,
                profile: profilePayload
            )
            QueueStore.shared.enqueue(request)
        } else {
            // Profile-only path: build a base CreateProfilePayload, fold staged props in.
            let payloadIdentity = PayloadIdentity(
                anonymousId: anonymousId,
                email: identity.email,
                phoneNumber: identity.phoneNumber,
                externalId: identity.externalId
            )
            var basePayload = RequestFactory.profilePayload(identity: payloadIdentity)
            let pendingProfile = Profile.updateProfileWithProperties(dict: snapshot)
            var attributes = basePayload.data.attributes
            PendingProfileFold.mergePendingAttributes(from: pendingProfile, into: &attributes)
            attributes.location = PendingProfileFold.mergedLocation(
                from: pendingProfile, into: attributes.location ?? .init()
            )
            basePayload = .init(data: .init(attributes: attributes))
            RequestEnqueuer.enqueueProfile(payload: basePayload)
        }
    }

    // MARK: - Test support

    /// Clears all staged properties. For test isolation only.
    package func reset() {
        lock.withLock { staged = [:] }
    }
}
