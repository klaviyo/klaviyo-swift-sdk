//
//  AuthTokenManagerRejectedTokenTests.swift
//  KlaviyoCore
//

@testable import KlaviyoCore
import Combine
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct AuthTokenManagerRejectedTokenTests {
    /// Fixed instant every test pins its clock and tokens to.
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Replacement

    @Test
    func replacesRejectedTokenWithOneProviderCall() async throws {
        let rejected = try token("rejected")
        let replacement = try token("replacement")
        let fixture = makeFixture()
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment() == 1 ? rejected : replacement
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        await manager.refreshRejectedToken()

        let delivered = await firstElement(of: stream)
        #expect(delivered == replacement)
        let invocations = await counter.value
        #expect(invocations == 2, "expected one provider call for the rejection, saw \(invocations - 1)")

        let served = try await manager.currentToken(mode: .background)
        #expect(served == replacement, "the rejected token must not be served after a refresh")
        let invocationsAfterRead = await counter.value
        #expect(invocationsAfterRead == 2, "the replacement must be served from cache")
    }

    @Test
    func republishesProviderTokenIdenticalToTheRejectedOne() async throws {
        let repeated = try token("repeated")
        let sentinel = try token("sentinel")
        let fixture = makeFixture()
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment() <= 2 ? repeated : sentinel
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        await manager.refreshRejectedToken()

        let invocations = await counter.value
        #expect(invocations == 2, "expected one provider call for the rejection, saw \(invocations - 1)")

        await manager.refreshRejectedToken()
        let delivered = await firstElement(of: stream)
        #expect(delivered == repeated, "a repeated token must be published, not swallowed")
    }

    @Test
    func joinsInFlightFetchInsteadOfStartingAnother() async throws {
        let onlyToken = try token("only")
        let manager = makeFixture().manager
        let counter = CallCounter()
        let fetchStarted = Latch()
        let releaseFetch = Latch()

        await manager.registerProvider {
            await counter.increment()
            await fetchStarted.open()
            await releaseFetch.wait()
            return onlyToken
        }
        // The eager warm-up fetch is now parked inside the provider.
        await fetchStarted.wait()
        let stream = await manager.refreshes()

        let refresh = Task { await manager.refreshRejectedToken() }
        for _ in 0..<100 {
            await Task.yield()
        }
        await releaseFetch.open()
        await refresh.value

        let delivered = await firstElement(of: stream)
        #expect(delivered == onlyToken)
        let invocations = await counter.value
        #expect(invocations == 1, "the rejection must join the in-flight fetch, saw \(invocations) calls")
    }

    @Test
    func makesOneProviderCallPerInvocationWithoutRetrying() async throws {
        let rejected = try token("rejected")
        let sentinel = try token("sentinel")
        let fixture = makeFixture()
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()

        await manager.registerProvider {
            switch await counter.increment() {
            case 1: return rejected
            case 2...4: throw ProviderTestError.network
            default: return sentinel
            }
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        for _ in 0..<3 {
            await manager.refreshRejectedToken()
        }

        let invocations = await counter.value
        #expect(invocations == 4, "expected one provider call per invocation, saw \(invocations - 1)")

        await manager.refreshRejectedToken()
        let delivered = await firstElement(of: stream)
        #expect(delivered == sentinel, "failed refreshes must publish nothing")
    }

    @Test
    func providerFailurePublishesNothingAndDropsRejectedToken() async throws {
        let rejected = try token("rejected")
        let replacement = try token("replacement")
        let sentinel = try token("sentinel")
        let fixture = makeFixture()
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()

        await manager.registerProvider {
            switch await counter.increment() {
            case 1: return rejected
            case 2: throw ProviderTestError.network
            case 3: return replacement
            default: return sentinel
            }
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        await manager.refreshRejectedToken()

        let served = try await manager.currentToken(mode: .background)
        #expect(served == replacement, "a failed refresh must still drop the rejected token")

        await manager.refreshRejectedToken()
        let delivered = await firstElement(of: stream)
        #expect(delivered == sentinel, "the failed refresh must publish nothing")
    }

    @Test
    func connectivityFailureArmsTheExistingConnectivityRetry() async throws {
        let rejected = try token("rejected")
        let replacement = try token("replacement")
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let reachability = TestReachability(.notReachable)
        let fixture = makeFixture(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() }),
            reachability: reachability
        )
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()

        await manager.registerProvider {
            switch await counter.increment() {
            case 1: return rejected
            case 2: throw URLError(.notConnectedToInternet)
            default: return replacement
            }
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        await manager.refreshRejectedToken()
        let armed = await manager.isAwaitingConnectivityRetryForTesting
        #expect(armed, "a connectivity failure must arm the one-shot connectivity retry")

        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))

        let delivered = await firstElement(of: stream)
        #expect(delivered == replacement)
        let invocations = await counter.value
        #expect(invocations == 3)
    }

    @Test
    func withoutProviderPublishesNothing() async throws {
        let sentinel = try token("sentinel")
        let manager = makeFixture().manager
        let stream = await manager.refreshes()

        await manager.refreshRejectedToken()

        await manager.registerProvider { sentinel }
        await manager.refreshRejectedToken()
        let delivered = await firstElement(of: stream)
        #expect(delivered == sentinel, "a refresh without a provider must publish nothing")
    }

    // MARK: - Fencing

    @Test
    func clearTokenStateMidFetchPublishesNothing() async throws {
        let rejected = try token("rejected")
        let stale = try token("stale")
        let sentinel = try token("sentinel")
        let fixture = makeFixture()
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()
        let fetchStarted = Latch()
        let releaseFetch = Latch()

        await manager.registerProvider {
            switch await counter.increment() {
            case 1:
                return rejected
            case 2:
                await fetchStarted.open()
                await releaseFetch.wait()
                return stale
            default:
                return sentinel
            }
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        let refresh = Task { await manager.refreshRejectedToken() }
        await fetchStarted.wait()
        await manager.clearTokenState()
        await releaseFetch.open()
        await refresh.value

        await manager.refreshRejectedToken()
        let delivered = await firstElement(of: stream)
        #expect(delivered == sentinel, "a refresh interrupted by clearTokenState must publish nothing")
    }

    @Test
    func providerChangeMidFetchPublishesNothing() async throws {
        let rejected = try token("rejected")
        let stale = try token("stale")
        let sentinel = try token("sentinel")
        let fixture = makeFixture()
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()
        let fetchStarted = Latch()
        let releaseFetch = Latch()

        await manager.registerProvider {
            guard await counter.increment() >= 2 else { return rejected }
            await fetchStarted.open()
            await releaseFetch.wait()
            return stale
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        let refresh = Task { await manager.refreshRejectedToken() }
        await fetchStarted.wait()
        await manager.registerProvider { sentinel }
        await releaseFetch.open()
        await refresh.value

        await manager.refreshRejectedToken()
        let delivered = await firstElement(of: stream)
        #expect(delivered == sentinel, "a refresh interrupted by a provider change must publish nothing")
    }

    // MARK: - Test helpers

    private var refSeconds: TimeInterval {
        referenceDate.timeIntervalSince1970
    }

    /// Mints an hour-long token, valid at ``referenceDate``, tagged with `subject`
    /// so tests can tell tokens apart.
    private func token(_ subject: String) throws -> String {
        try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": subject]
        )
    }

    private struct Fixture {
        let manager: AuthTokenManager
        let clock: TestClock
        let gate: SleepGate
    }

    private func makeFixture(
        lifeCycle: AppLifeCycleEvents = noopLifecycle(),
        reachability: TestReachability = TestReachability()
    ) -> Fixture {
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(
            lifeCycle: lifeCycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        return Fixture(manager: manager, clock: clock, gate: gate)
    }

    /// Suspends until the eager warm-up fetch has cached its token and parked
    /// its scheduled refresh.
    private func warmUp(counter: CallCounter, gate: SleepGate) async throws {
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)
    }
}

// MARK: - Scheduled refresh

extension AuthTokenManagerRejectedTokenTests {
    @Test
    func cancelsTheRejectedTokensScheduledRefresh() async throws {
        // iat=ref-60, exp=ref+40 → the scheduled refresh lands at ref+10.
        let rejected = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "rejected"]
        )
        let unexpected = try token("unexpected")
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let fixture = makeFixture(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        )
        let manager = fixture.manager
        let clock = fixture.clock
        let gate = fixture.gate
        let counter = CallCounter()

        await manager.registerProvider {
            switch await counter.increment() {
            case 1: return rejected
            case 2: throw ProviderTestError.network
            default: return unexpected
            }
        }
        try await warmUp(counter: counter, gate: gate)

        await manager.refreshRejectedToken()

        // Wake the rejected token's sleep past its target time.
        clock.set(referenceDate.addingTimeInterval(20))
        await gate.release()
        for _ in 0..<100 {
            await Task.yield()
        }
        let invocationsAfterWake = await counter.value
        #expect(
            invocationsAfterWake == 2,
            "the old scheduled refresh must not fire, saw \(invocationsAfterWake) calls"
        )

        lifecycleSubject.send(.foregrounded)
        for _ in 0..<100 {
            await Task.yield()
        }
        let invocationsAfterForeground = await counter.value
        #expect(
            invocationsAfterForeground == 2,
            "a foreground must not retry the old refresh target, saw \(invocationsAfterForeground) calls"
        )
    }
}

// MARK: - Timeout

extension AuthTokenManagerRejectedTokenTests {
    @Test
    func hungProviderTimesOutWithoutPublishing() async throws {
        let rejected = try token("rejected")
        let replacement = try token("replacement")
        let sentinel = try token("sentinel")
        let fixture = makeFixture()
        let manager = fixture.manager
        let gate = fixture.gate
        let counter = CallCounter()
        let releaseFetch = Latch()
        let nextToken = TokenBox(replacement)

        await manager.registerProvider {
            guard await counter.increment() >= 2 else { return rejected }
            await releaseFetch.wait()
            return await nextToken.value
        }
        try await warmUp(counter: counter, gate: gate)
        let stream = await manager.refreshes()

        await manager.refreshRejectedToken(timeoutSeconds: 0.05)
        let invocations = await counter.value
        #expect(invocations == 2)

        let next = Task { await manager.refreshRejectedToken() }
        await releaseFetch.open()
        await next.value
        await nextToken.set(sentinel)
        await manager.refreshRejectedToken()

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(
            [first, second] == [replacement, sentinel],
            "the timed-out refresh must publish nothing; the next one must publish its token"
        )
    }
}
#endif
