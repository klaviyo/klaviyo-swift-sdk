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
        let stream = await manager.refreshes()

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
        let fixture = try await makeWarmFixture { _ in
            await releaseFetch.wait()
            return replacement
        }
        let watchdogFires = CallCounter()
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            _ = await watchdogFires.increment()
            await releaseFetch.open()
        }
        defer { watchdog.cancel() }

        await fixture.manager.refreshRejectedToken(timeoutSeconds: 0.05)
        let fires = await watchdogFires.value
        #expect(fires == 0, "the wait must end on the timeout, not when the provider is released")
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
        let stream = await manager.refreshes()

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
        provider: @escaping @Sendable (Int) async throws -> String
    ) async throws -> Fixture {
        let rejected = try rejected ?? token("rejected")
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: lifeCycle, clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            let call = await counter.increment()
            guard call > 1 else { return rejected }
            return try await provider(call)
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)
        let refreshes = await manager.refreshes()
        return Fixture(manager: manager, clock: clock, gate: gate, counter: counter, refreshes: refreshes)
    }

    private func yieldRepeatedly() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }
}
#endif
