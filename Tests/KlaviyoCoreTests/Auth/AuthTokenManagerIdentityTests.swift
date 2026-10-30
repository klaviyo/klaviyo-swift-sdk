//
//  AuthTokenManagerIdentityTests.swift
//  KlaviyoCore
//
//  Covers how the current profile identity gates provider calls and binds the
//  cached token to a profile.
//

@testable import KlaviyoCore
import Combine
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct AuthTokenManagerIdentityTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let anonymous = ProfileData(anonymousId: "anon")
    private let profileA = ProfileData(email: "a@example.com", anonymousId: "anon")

    // MARK: - No identifier

    @Test
    func anonymousProfileNeverReachesProviderOrArmsRetry() async throws {
        let identity = IdentityStore(initialIdentity: anonymous)
        let manager = AuthTokenManager(
            currentDate: { Date() },
            reachabilityStatus: { .reachableViaWiFi },
            identity: identity,
            fetchTimeoutSleep: neverTimesOut
        )
        let counter = CallCounter()
        let token = try makeJWT()
        await manager.registerProvider {
            await counter.increment()
            if !identity.current.isIdentified {
                throw URLError(.notConnectedToInternet)
            }
            return token
        }

        await #expect(throws: AuthTokenError.noProfileIdentifier) {
            _ = try await manager.currentToken()
        }
        await #expect(throws: AuthTokenError.noProfileIdentifier) {
            _ = try await manager.currentToken(mode: .background)
        }
        let anonymousInvocations = await counter.value
        let awaitingRetry = await manager.isAwaitingConnectivityRetryForTesting
        #expect(anonymousInvocations == 0)
        #expect(!awaitingRetry)

        identity.update(profileA)
        let identifiedToken = try await manager.currentToken(mode: .background)
        let identifiedInvocations = await counter.value
        #expect(identifiedToken == token)
        #expect(identifiedInvocations == 1)
    }

    @Test
    func scheduledRefreshForOutgoingProfileIsCancelledOnceProfileIsAnonymous() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let observation = CancellationObservation()
        let manager = AuthTokenManager(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() }),
            currentDate: { clock.now() },
            sleep: {
                await gate.sleep($0)
                await observation.record(Task.isCancelled)
            },
            identity: identity,
            fetchTimeoutSleep: neverTimesOut
        )
        let counter = CallCounter()
        let token = try makeJWT(issuedAt: refSeconds - 60, expiresAt: refSeconds + 3600)
        await manager.registerProvider {
            await counter.increment()
            return token
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        identity.update(anonymous)
        await manager.clearReplacedProfileTokenState()
        // The refresh target is 90% of the token's lifetime: iat + 0.9 * 3660s.
        clock.set(referenceDate.addingTimeInterval(3234))
        await gate.release()
        let refreshWasCancelled = await observation.wait()

        #expect(refreshWasCancelled, "the refresh scheduled for the outgoing profile must be cancelled")
    }

    // MARK: - Profile-bound cache

    @Test
    func cachedTokenIsNotServedAfterProfileReplacement() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        await manager.registerProvider {
            let invocation = await counter.increment()
            return try makeJWT(extraClaims: ["sub": "token-\(invocation)"])
        }
        let tokenA = try await manager.currentToken(mode: .background)

        identity.update(profileB)
        let tokenB = try await manager.currentToken(mode: .background)

        #expect(tokenB != tokenA)
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    @Test
    func cachedTokenIsServedAcrossCompatibleChanges() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        await manager.registerProvider {
            let invocation = await counter.increment()
            return try makeJWT(extraClaims: ["sub": "token-\(invocation)"])
        }
        let token = try await manager.currentToken(mode: .background)

        identity.update(ProfileData(email: "a@example.com", externalId: "ext-1", anonymousId: "anon"))
        let afterAddition = try await manager.currentToken(mode: .background)
        identity.update(ProfileData(externalId: "ext-1", anonymousId: "anon"))
        let afterRemoval = try await manager.currentToken(mode: .background)

        #expect(afterAddition == token)
        #expect(afterRemoval == token)
        let invocations = await counter.value
        #expect(invocations == 1)
    }

    @Test
    func chainOfCompatibleThenReplacingChangesDoesNotServeOutgoingToken() async throws {
        let identity = IdentityStore(initialIdentity: ProfileData(email: "a@example.com"))
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        await manager.registerProvider {
            let invocation = await counter.increment()
            return try makeJWT(extraClaims: ["sub": "token-\(invocation)"])
        }
        let outgoingToken = try await manager.currentToken(mode: .background)

        identity.update(ProfileData(email: "a@example.com", phoneNumber: "+15550000001"))
        identity.update(ProfileData(email: "a@example.com", phoneNumber: "+15550000002"))
        let incomingToken = try await manager.currentToken(mode: .background)

        #expect(incomingToken != outgoingToken)
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    @Test
    func companySwitchShapeDoesNotServeOutgoingTokenAndGatesProviderWhileAnonymous() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        await manager.registerProvider {
            let invocation = await counter.increment()
            return try makeJWT(extraClaims: ["sub": "token-\(invocation)"])
        }
        let outgoingToken = try await manager.currentToken(mode: .background)

        identity.update(ProfileData(anonymousId: "anon-new"))
        await #expect(throws: AuthTokenError.noProfileIdentifier) {
            _ = try await manager.currentToken(mode: .background)
        }
        let invocationsWhileAnonymous = await counter.value

        identity.update(ProfileData(email: "a@example.com", anonymousId: "anon-new"))
        let incomingToken = try await manager.currentToken(mode: .background)
        let invocationsAfterIdentified = await counter.value

        #expect(invocationsWhileAnonymous == 1)
        #expect(incomingToken != outgoingToken)
        #expect(invocationsAfterIdentified == 2)
    }

    @Test
    func fetchCompletingAfterProfileReplacementIsDroppedAndNotCached() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        let firstFetchRelease = Latch()
        let staleToken = try makeJWT(extraClaims: ["sub": "stale"])
        let freshToken = try makeJWT(extraClaims: ["sub": "fresh"])
        await manager.registerProvider {
            let invocation = await counter.increment()
            if invocation == 1 {
                await firstFetchRelease.wait()
                return staleToken
            }
            return freshToken
        }
        let outgoingCaller = Task { try await manager.currentToken(mode: .background) }
        try await counter.waitFor(atLeast: 1)

        identity.update(profileB)
        await firstFetchRelease.open()

        let outgoingCallerToken = try await outgoingCaller.value
        let token = try await manager.currentToken(mode: .background)
        #expect(outgoingCallerToken == freshToken)
        #expect(token == freshToken)
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    // MARK: - Warm-up

    @Test
    func warmUpGatedWhileAnonymousRunsOnceWhenProfileBecomesIdentified() async throws {
        let identity = IdentityStore(initialIdentity: anonymous)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        let token = try makeJWT()
        await manager.registerProvider {
            await counter.increment()
            return token
        }
        await #expect(throws: AuthTokenError.noProfileIdentifier) {
            _ = try await manager.currentToken(mode: .background)
        }
        let invocationsWhileAnonymous = await counter.value
        #expect(invocationsWhileAnonymous == 0)

        identity.update(profileA)
        try await counter.waitFor(atLeast: 1)
        identity.update(ProfileData(email: "a@example.com", externalId: "ext-1", anonymousId: "anon"))
        let served = try await manager.currentToken(mode: .background)

        let invocations = await counter.value
        #expect(served == token)
        #expect(invocations == 1)
    }

    // MARK: - Republish

    @Test
    func republishDeliversCachedTokenAgainAndIgnoresAStaleGeneration() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        await manager.registerProvider {
            let invocation = await counter.increment()
            return try makeJWT(extraClaims: ["sub": "token-\(invocation)"])
        }
        let outgoing = try await manager.currentTokenRefresh(mode: .background)
        let stream = await manager.tokens()
        var iterator = stream.makeAsyncIterator()

        await manager.republish(outgoing)
        let republished = await iterator.next()
        identity.update(profileB)
        await manager.republish(outgoing)
        let incoming = try await manager.currentToken(mode: .background)
        let next = await iterator.next()

        #expect(republished == outgoing.token)
        #expect(next == incoming, "a token of an outgoing generation must not be republished")
        #expect(incoming != outgoing.token)
    }

    @Test
    func rejectedTokenRefreshWhileAnonymousNeitherCallsProviderNorPublishes() async throws {
        let identity = IdentityStore(initialIdentity: anonymous)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        let token = try makeJWT()
        await manager.registerProvider {
            await counter.increment()
            return token
        }
        let stream = await manager.tokens()
        var iterator = stream.makeAsyncIterator()

        await manager.refreshRejectedToken()
        identity.update(profileA)
        let published = await iterator.next()

        let invocations = await counter.value
        #expect(published == token)
        #expect(invocations == 1, "only the warm-up after identification may call the provider")
    }

    // MARK: - Stale reads

    @Test
    func staleIdentityReadDoesNotMoveGenerationBackwards() {
        let identity = ControllableIdentity(VersionedProfile(profile: profileA, sequence: 0))
        let tracker = IdentityGenerationTracker(identity: identity)
        identity.emit(VersionedProfile(profile: profileB, sequence: 1))
        let afterReplacement = tracker.snapshot()

        identity.setStaleRead(VersionedProfile(profile: profileA, sequence: 0))
        let afterStaleRead = tracker.snapshot()

        #expect(afterReplacement.profile == profileB)
        #expect(afterReplacement.generation == 1)
        #expect(afterStaleRead == afterReplacement)
    }

    @Test
    func lateDeliveryOfOlderValueIsIgnored() {
        let identity = ControllableIdentity(VersionedProfile(profile: profileA, sequence: 0))
        let tracker = IdentityGenerationTracker(identity: identity)
        identity.emit(VersionedProfile(profile: profileB, sequence: 2))

        identity.emit(VersionedProfile(profile: profileA, sequence: 1))

        let snapshot = tracker.snapshot()
        #expect(snapshot.profile == profileB)
        #expect(snapshot.generation == 1)
    }

    private var profileB: ProfileData {
        ProfileData(email: "b@example.com", anonymousId: "anon-b")
    }

    private var refSeconds: TimeInterval {
        referenceDate.timeIntervalSince1970
    }
}

extension AuthTokenManagerIdentityTests {
    // MARK: - Replacement clear arriving late

    @Test
    func lateReplacementClearLeavesFetchForNewProfileRunning() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        let incomingFetchRelease = Latch()
        let incomingToken = try makeJWT(extraClaims: ["sub": "incoming"])
        await manager.registerProvider {
            let invocation = await counter.increment()
            if invocation == 1 { return try makeJWT(extraClaims: ["sub": "outgoing"]) }
            await incomingFetchRelease.wait()
            return incomingToken
        }
        _ = try await manager.currentToken(mode: .background)

        identity.update(profileB)
        let incomingCaller = Task { try await manager.currentToken(mode: .background) }
        try await counter.waitFor(atLeast: 2)
        await manager.clearReplacedProfileTokenState()
        await incomingFetchRelease.open()

        let token = try await incomingCaller.value
        #expect(token == incomingToken)
        let invocations = await counter.value
        #expect(invocations == 2)
    }

    @Test
    func lateReplacementClearKeepsRefreshScheduleForNewProfile() async throws {
        let identity = IdentityStore(initialIdentity: profileA)
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = AuthTokenManager(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() }),
            currentDate: { clock.now() },
            sleep: { await gate.sleep($0) },
            identity: identity,
            fetchTimeoutSleep: neverTimesOut
        )
        let counter = CallCounter()
        let refreshedToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "refreshed"]
        )
        let issuedAt = refSeconds - 60
        let shortLived = { (subject: String) in
            try makeJWT(issuedAt: issuedAt, expiresAt: issuedAt + 100, extraClaims: ["sub": subject])
        }
        await manager.registerProvider {
            switch await counter.increment() {
            case 1: return try shortLived("outgoing")
            case 2: return try shortLived("incoming")
            default: return refreshedToken
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        identity.update(profileB)
        _ = try await manager.currentToken(mode: .background)
        await gate.waitUntilSleeping(atLeast: 2)
        await manager.clearReplacedProfileTokenState()
        let refreshes = await manager.tokens()

        // Both tokens refresh at exp - 30s; the outgoing profile's sleep was cancelled.
        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        await gate.release()
        let delivered = await firstElement(of: refreshes)

        #expect(delivered == refreshedToken)
    }

    @Test
    func profileIdentifiedWhileWarmUpIsGatedStillRunsWarmUpOnce() async throws {
        let identity = ControllableIdentity(VersionedProfile(profile: anonymous, sequence: 0))
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        let token = try makeJWT()
        let identifiedProfile = VersionedProfile(profile: profileA, sequence: 1)
        await manager.setWarmUpGatedHookForTesting { identity.emit(identifiedProfile) }
        await manager.registerProvider {
            await counter.increment()
            return token
        }

        try await counter.waitFor(atLeast: 1)
        let served = try await manager.currentToken(mode: .background)

        let invocations = await counter.value
        #expect(served == token)
        #expect(invocations == 1)
    }
}
#endif
