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

    @Test
    func replacesRejectedTokenWithOneProviderCall() async throws {
        let replacement = try token("replacement")
        let fixture = try await makeWarmFixture { _ in replacement }

        await fixture.manager.refreshRejectedToken()

        let served = try await fixture.manager.currentToken(mode: .background)
        try #require(served == replacement, "the rejected token must not be served after a refresh")
        let invocations = await fixture.counter.value
        #expect(invocations == 2, "expected one provider call, then the replacement served from cache")
        let delivered = await firstElement(of: fixture.refreshes)
        #expect(delivered == replacement)
    }

    @Test
    func joinsInFlightFetchInsteadOfStartingAnother() async throws {
        let onlyToken = try token("only")
        let manager = makeColdManager()
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
        let stream = await manager.tokens()

        let refresh = Task { await manager.refreshRejectedToken() }
        await yieldRepeatedly()
        await releaseFetch.open()
        await refresh.value

        let delivered = await firstElement(of: stream)
        #expect(delivered == onlyToken)
        let invocations = await counter.value
        #expect(invocations == 1, "the rejection must join the in-flight fetch, saw \(invocations) calls")
    }

    @Test
    func overlappingCallsShareOneReplacement() async throws {
        let replacement = try token("replacement")
        let fetchStarted = Latch()
        let releaseFetch = Latch()
        let fixture = try await makeWarmFixture { _ in
            await fetchStarted.open()
            await releaseFetch.wait()
            return replacement
        }
        let manager = fixture.manager

        let first = Task { await manager.refreshRejectedToken(timeoutSeconds: 3600) }
        await fetchStarted.wait()
        let secondReturns = CallCounter()
        let second = Task {
            await manager.refreshRejectedToken(timeoutSeconds: 0)
            await secondReturns.increment()
            return await manager.isCurrentToken(replacement)
        }
        await manager.waitForRejectedTokenRefreshCallsForTesting(atLeast: 2)
        let joined = await manager.joinedRejectedTokenRefreshesForTesting
        try #require(joined == 1, "the overlapping call must join the running replacement")
        await yieldRepeatedly()
        let returnsWhileParked = await secondReturns.value
        #expect(
            returnsWhileParked == 0,
            "an overlapping call must wait for the shared replacement, not its own budget"
        )
        await releaseFetch.open()
        await first.value

        let secondSawReplacement = await second.value
        #expect(secondSawReplacement)
        let invocations = await fixture.counter.value
        #expect(invocations == 2, "expected one provider call for both, saw \(invocations - 1)")
        let delivered = await firstElement(of: fixture.refreshes)
        #expect(delivered == replacement)
    }

    @Test
    func callAfterTheSharedReplacementFinishedStartsANewOne() async throws {
        let firstReplacement = try token("first")
        let secondReplacement = try token("second")
        let fixture = try await makeWarmFixture { call in
            call == 2 ? firstReplacement : secondReplacement
        }

        await fixture.manager.refreshRejectedToken()
        await fixture.manager.refreshRejectedToken()

        let invocations = await fixture.counter.value
        #expect(invocations == 3, "expected one provider call per finished replacement")
        let served = try await fixture.manager.currentToken(mode: .background)
        #expect(served == secondReplacement)
    }

    @Test
    func resetEndsTheSharedReplacement() async throws {
        let replacement = try token("replacement")
        let hungFetchStarted = Latch()
        let releaseHungFetch = Latch()
        let fixture = try await makeWarmFixture { call in
            if call == 2 {
                await hungFetchStarted.open()
                await releaseHungFetch.wait()
            }
            return replacement
        }
        let manager = fixture.manager
        let watchdog = Watchdog(opening: hungFetchStarted, releaseHungFetch)
        defer { watchdog.cancel() }

        let hung = Task { await manager.refreshRejectedToken(timeoutSeconds: 60) }
        await hungFetchStarted.wait()
        let firedBeforeFetch = await watchdog.fired
        try #require(!firedBeforeFetch, "the refresh never called the provider")
        await manager.clearTokenState()
        await manager.refreshRejectedToken()

        let fired = await watchdog.fired
        #expect(!fired, "a call after a reset must not wait on the replacement the reset ended")
        let invocations = await fixture.counter.value
        #expect(invocations == 3)
        let cached = await manager.isCurrentToken(replacement)
        #expect(cached)
        await releaseHungFetch.open()
        await hung.value
    }

    @Test
    func companyChangeEndsTheSharedReplacement() async throws {
        let config = SDKConfigStore(initialConfig: KlaviyoConfig(apiKey: "A"))
        let tokenA = try makeJWT(extraClaims: ["sub": "A"])
        let tokenB = try makeJWT(extraClaims: ["sub": "B"])
        let hungFetchStarted = Latch()
        let releaseHungFetch = Latch()
        let calls = CallCounter()
        let manager = AuthTokenManager(currentDate: { Date() }, config: config)
        await manager.registerProvider {
            switch await calls.increment() {
            case 1:
                return tokenA
            case 2:
                await hungFetchStarted.open()
                await releaseHungFetch.wait()
                return tokenA
            default:
                return tokenB
            }
        }
        let warm = try await manager.currentToken(mode: .background)
        try #require(warm == tokenA)
        let watchdog = Watchdog(opening: hungFetchStarted, releaseHungFetch)
        defer { watchdog.cancel() }

        let hung = Task { await manager.refreshRejectedToken(timeoutSeconds: 60) }
        await hungFetchStarted.wait()
        config.update(KlaviyoConfig(apiKey: "B"))
        let afterSwitch = try await manager.currentToken(mode: .background)
        #expect(afterSwitch == tokenB)
        await manager.refreshRejectedToken()

        let fired = await watchdog.fired
        #expect(!fired, "a call after a company change must not wait on the replacement it ended")
        let invocations = await calls.value
        #expect(invocations == 4)
        let cached = await manager.isCurrentToken(tokenB)
        #expect(cached)
        await releaseHungFetch.open()
        await hung.value
        await manager.unregisterProvider()
    }

    @Test
    func failedRefreshesMakeOneCallEachAndStillDropTheRejectedToken() async throws {
        let replacement = try token("replacement")
        let fixture = try await makeWarmFixture { call in
            guard call > 4 else { throw ProviderTestError.network }
            return replacement
        }

        for _ in 0..<3 {
            await fixture.manager.refreshRejectedToken()
        }

        let invocations = await fixture.counter.value
        #expect(invocations == 4, "expected one provider call per invocation, saw \(invocations - 1)")
        let served = try await fixture.manager.currentToken(mode: .background)
        try #require(served == replacement, "a failed refresh must still drop the rejected token")
        let delivered = await firstElement(of: fixture.refreshes)
        #expect(delivered == replacement, "failed refreshes must publish nothing")
    }

    @Test
    func cancelsTheRejectedTokensScheduledRefresh() async throws {
        // iat=ref-60, exp=ref+40 → the scheduled refresh lands at ref+10.
        let rejected = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "rejected"]
        )
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let fixture = try await makeWarmFixture(
            rejected: rejected,
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        ) { _ in
            throw ProviderTestError.network
        }

        await fixture.manager.refreshRejectedToken()

        // Wake the rejected token's sleep past its target time.
        fixture.clock.set(referenceDate.addingTimeInterval(20))
        await fixture.gate.release()
        await yieldRepeatedly()
        let invocationsAfterWake = await fixture.counter.value
        #expect(invocationsAfterWake == 2, "the old scheduled refresh must not fire")

        lifecycleSubject.send(.foregrounded)
        await yieldRepeatedly()
        let invocationsAfterForeground = await fixture.counter.value
        #expect(invocationsAfterForeground == 2, "a foreground must not retry the old refresh target")
    }

    @Test
    func hungProviderTimesOutAndItsLateTokenIsPublished() async throws {
        let replacement = try token("replacement")
        let releaseFetch = Latch()
        let hungProviderBudget: TimeInterval = 0.05
        let fixture = try await makeWarmFixture(
            fetchTimeoutSleep: timeoutSleep(expiring: [hungProviderBudget])
        ) { _ in
            await releaseFetch.wait()
            return replacement
        }
        let watchdog = Watchdog(opening: releaseFetch)
        defer { watchdog.cancel() }

        await fixture.manager.refreshRejectedToken(timeoutSeconds: 0.05)
        let fired = await watchdog.fired
        #expect(!fired, "the wait must end on the timeout, not when the provider is released")
        let invocations = await fixture.counter.value
        try #require(invocations == 2)

        await releaseFetch.open()
        let late = await firstElement(of: fixture.refreshes)
        #expect(late == replacement, "the timed-out fetch must publish its late token")
    }

    @Test
    func withoutProviderPublishesNothing() async throws {
        let sentinel = try token("sentinel")
        let manager = makeColdManager()
        let stream = await manager.tokens()

        await manager.refreshRejectedToken()
        await manager.registerProvider { sentinel }

        let delivered = await firstElement(of: stream)
        #expect(delivered == sentinel, "a refresh without a provider must publish nothing")
    }
}

// MARK: - Test helpers

extension AuthTokenManagerRejectedTokenTests {
    private struct Fixture {
        let manager: AuthTokenManager
        let clock: TestClock
        let gate: SleepGate
        let counter: CallCounter
        /// Subscribed after the warm-up token was published.
        let refreshes: AsyncStream<String>
    }

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

    private func makeColdManager() -> AuthTokenManager {
        makeManager(lifeCycle: noopLifecycle(), clock: TestClock(referenceDate), gate: SleepGate())
    }

    /// Registers a provider that returns `rejected` (an hour-long token by default)
    /// on its warm-up call and hands every later call, numbered from 2, to `provider`.
    /// Returns once the warm-up token is cached and its scheduled refresh is parked.
    private func makeWarmFixture(
        rejected: String? = nil,
        lifeCycle: AppLifeCycleEvents = noopLifecycle(),
        fetchTimeoutSleep: @escaping @Sendable (UInt64) async -> Void = neverTimesOut,
        provider: @escaping @Sendable (Int) async throws -> String
    ) async throws -> Fixture {
        let rejected = try rejected ?? token("rejected")
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(
            lifeCycle: lifeCycle, clock: clock, gate: gate, fetchTimeoutSleep: fetchTimeoutSleep
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let call = await counter.increment()
            guard call > 1 else { return rejected }
            return try await provider(call)
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)
        let refreshes = await manager.tokens()
        return Fixture(manager: manager, clock: clock, gate: gate, counter: counter, refreshes: refreshes)
    }

    /// Opens `latches` if the test is still running after a minute, so a wait that
    /// never ends fails the test instead of hanging it. ``fired`` reports whether it did.
    private struct Watchdog {
        private let fires: CallCounter
        private let task: Task<Void, Never>

        init(opening latches: Latch...) {
            let fires = CallCounter()
            self.fires = fires
            task = Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                await fires.increment()
                for latch in latches {
                    await latch.open()
                }
            }
        }

        var fired: Bool {
            get async { await fires.value > 0 }
        }

        func cancel() {
            task.cancel()
        }
    }

    private func yieldRepeatedly() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }
}
#endif
