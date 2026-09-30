//
//  ProfilePropertyBuffer.swift
//
//
//  Created by Isobelle Lim on 9/11/26.
//

import AnyCodable
import Foundation
import KlaviyoCore

/// KlaviyoSwift-side staging for profile properties set via `setProfileProperty`. Staged props are
/// folded into `QueueStore` just before the `RequestQueue` actor drains (`willDrain`): with a push
/// token → a `registerPushToken` request; otherwise → a `createProfile` request. Identity is read
/// fresh from `IdentityStore.shared` at flush time.
///
/// Thread-safety: `staged` is `NSLock`-guarded; `stage` may run on any thread. `flushIntoQueue`
/// snapshots-and-clears the dict atomically up front so the flush sees a consistent view even if a
/// concurrent `stage` races it.
final class ProfilePropertyBuffer: @unchecked Sendable {
    static let shared = ProfilePropertyBuffer()

    private let lock = NSLock()
    private var staged: [Profile.ProfileKey: AnyEncodable] = [:]
    private var generation = 0

    // MARK: - API

    /// Stages a single property key/value. Safe to call from any thread.
    func stage(_ profileKey: Profile.ProfileKey, _ value: AnyEncodable) {
        lock.withLock { staged[profileKey] = value }
    }

    /// Snapshot-and-clears the staged dict, folds the properties into the appropriate request, and
    /// enqueues it. No-op when the buffer is empty or when `apiKey` is not yet configured.
    func flushIntoQueue() async {
        // Snapshot-and-clear under the lock so a concurrent `stage` call cannot race.
        let (snapshot, capturedGeneration) = lock.withLock {
            defer { staged = [:] }
            return (staged, generation)
        }

        guard !snapshot.isEmpty else { return }

        guard let apiKey = SDKConfigStore.shared.current.apiKey else {
            restore(snapshot, generation: capturedGeneration)
            environment.emitDeveloperWarning(
                "ProfilePropertyBuffer.flushIntoQueue: apiKey not set; staged properties retained"
            )
            return
        }

        // Read identity + push token once, up front, so the fold and the token-vs-profile decision
        // below see one consistent view.
        let identity = IdentityStore.shared.current
        let pushTokenData = IdentityStore.shared.pushToken
        guard let anonymousId = identity.anonymousId else {
            restore(snapshot, generation: capturedGeneration)
            environment.emitDeveloperWarning(
                "ProfilePropertyBuffer.flushIntoQueue: missing anonymousId; staged properties retained"
            )
            return
        }

        guard lock.withLock({ generation == capturedGeneration }) else { return }

        if let tokenData = pushTokenData {
            enqueueTokenRequest(
                apiKey: apiKey, anonymousId: anonymousId, identity: identity,
                tokenData: tokenData, snapshot: snapshot
            )
        } else {
            enqueueProfileRequest(anonymousId: anonymousId, identity: identity, snapshot: snapshot)
        }
    }

    /// Restores a snapshot into `staged` so retained props aren't dropped, without clobbering any
    /// props staged since the flush began.
    private func restore(_ snapshot: [Profile.ProfileKey: AnyEncodable], generation capturedGeneration: Int) {
        lock.withLock {
            guard generation == capturedGeneration else { return }
            staged = snapshot.merging(staged) { _, newer in newer }
        }
    }

    /// Push-token path: fold staged props into a `Profile` → `ProfilePayload` → `tokenRequest`.
    /// Must NOT use `RequestEnqueuer.enqueuePushToken` — it builds from flat identity only and drops
    /// structured attributes (firstName, lastName, title, etc.).
    private func enqueueTokenRequest(
        apiKey: String,
        anonymousId: String,
        identity: ProfileData,
        tokenData: PushTokenData,
        snapshot: [Profile.ProfileKey: AnyEncodable]
    ) {
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
    }

    /// Profile-only path: build a base `CreateProfilePayload` from identity, fold staged props in.
    private func enqueueProfileRequest(
        anonymousId: String,
        identity: ProfileData,
        snapshot: [Profile.ProfileKey: AnyEncodable]
    ) {
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

    /// Drops all staged properties. Called from `KlaviyoCommands.resetProfile()`,
    /// `KlaviyoCommands.enqueueProfile()`, and `KlaviyoCommands.initialize()` so
    /// staged props never leak onto a new identity. Also used for test isolation.
    func reset() {
        lock.withLock {
            staged = [:]
            generation &+= 1
        }
    }
}
