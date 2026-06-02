//
//  AuthTokenManagerRefreshTests.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-29.
//

@testable import KlaviyoCore
import Combine
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct AuthTokenManagerRefreshTests {
    /// Fixed instant every test pins its clock and tokens to. Using a constant
    /// (rather than `Date()`) makes the suite immune to real elapsed time: the
    /// manager's clock only moves when a test moves it, so token validity
    /// windows and refresh-fire times never depend on how slow or loaded the
    /// host is. This is what makes the real-time paths below deterministic on CI.
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Scheduling formula (pure-function tests, no real time)

    @Test
    func refreshTargetLandsAt90PercentOfTokenLifetime() {
        // issued=1000, expires=1200 → 200s lifetime → ideal target at 1180.
        // Lifetime is large enough that the upper clamp (exp-30=1170) and the
        // lower clamp (now+5=1005) are both satisfied by the ideal point.
        // But wait: ideal=1180 > upper=1170, so the upper clamp wins → 1170.
        let issued = Date(timeIntervalSince1970: 1000)
        let expires = Date(timeIntervalSince1970: 1200)
        let token = ValidatedToken(rawToken: "ignored", expiresAt: expires, issuedAt: issued)

        let target = AuthTokenManager.refreshTarget(for: token, currentDate: issued)

        // The 0.9-of-lifetime point lands past `exp - leeway`, so the upper
        // clamp takes effect.
        #expect(target == Date(timeIntervalSince1970: 1170))
    }

    @Test
    func refreshTargetUsesIdealPointWhenInsideClamps() {
        // Need ideal target inside `[now + 5, exp - 30]`. A 1-hour token gives
        // plenty of room: issued=1000, expires=4600 (3600s lifetime) → ideal
        // at 1000 + 0.9*3600 = 4240. Upper=4570, lower=1005. Ideal is
        // comfortably between, so no clamp fires.
        let issued = Date(timeIntervalSince1970: 1000)
        let expires = Date(timeIntervalSince1970: 4600)
        let token = ValidatedToken(rawToken: "ignored", expiresAt: expires, issuedAt: issued)

        let target = AuthTokenManager.refreshTarget(for: token, currentDate: issued)

        #expect(target == Date(timeIntervalSince1970: 4240))
    }

    @Test
    func refreshTargetClampsToExpMinusLeewayWhenIdealExceedsUpperBound() {
        // Short-lifetime token where 0.9 of lifetime overshoots `exp - 30s`.
        // issued=0, expires=100, ideal=90, upper=70, lower=5 → target = 70.
        let issued = Date(timeIntervalSince1970: 0)
        let expires = Date(timeIntervalSince1970: 100)
        let token = ValidatedToken(rawToken: "ignored", expiresAt: expires, issuedAt: issued)

        let target = AuthTokenManager.refreshTarget(for: token, currentDate: issued)

        #expect(target == Date(timeIntervalSince1970: 70))
    }

    @Test
    func refreshTargetClampsToNowPlusFiveWhenIdealAlreadyPast() {
        // Token issued in the deep past — ideal target is behind us. The
        // lower clamp should bump it to `now + 5s` so the refresh task doesn't
        // spin-loop. now=1000, issued=0, expires=10 → ideal=9, upper=-20,
        // lower=1005. The min(ideal, upper) = -20 is way past, so
        // max(lower, that) = 1005.
        let issued = Date(timeIntervalSince1970: 0)
        let expires = Date(timeIntervalSince1970: 10)
        let currentDate = Date(timeIntervalSince1970: 1000)
        let token = ValidatedToken(rawToken: "ignored", expiresAt: expires, issuedAt: issued)

        let target = AuthTokenManager.refreshTarget(for: token, currentDate: currentDate)

        #expect(target == Date(timeIntervalSince1970: 1005))
    }

    // MARK: - Refresh fires (virtual-time, end-to-end)

    @Test
    func refreshFiresAtScheduledTimeAndChainsNextSchedule() async throws {
        // iat=ref-60, exp=ref+40 → 100s lifetime; ideal=ref+30, upper=exp-30=
        // ref+10, lower=ref+5 → refresh target lands at the upper clamp, ref+10.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        // Long-lived so it validates once the clock has advanced to the fire time.
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: noopLifecycle(), clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            return invocation == 1 ? firstToken : secondToken
        }
        try await counter.waitFor(atLeast: 1)

        // The scheduled refresh is armed and parked in the gate (which also
        // confirms firstToken is cached). Subscribe, then drive virtual time to
        // the fire point and release the parked sleep.
        await gate.waitUntilSleeping(atLeast: 1)
        let stream = await manager.refreshes()

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()

        // The proactive refresh fetched secondToken and broadcast it...
        let delivered = await firstElement(of: stream)
        #expect(delivered == secondToken)

        // ...and wrote it to the cache.
        let cached = try await manager.currentToken(mode: .background)
        #expect(cached == secondToken)
    }

    // MARK: - Foreground transitions

    @Test
    func foregroundWithStillValidTokenIsNoOp() async throws {
        // Hour-long token; foreground transition should be a no-op (refresh
        // is far in the future, cache is healthy). Assert by counting
        // provider invocations: exactly one (initial fetch) is expected.
        let validToken = try makeJWT(issuedAt: refSeconds - 60, expiresAt: refSeconds + 3600)
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: lifecycle, clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            return validToken
        }
        try await counter.waitFor(atLeast: 1)
        // Confirm the token is cached and the (far-future) refresh is armed
        // before we foreground, so the no-op path is what's exercised.
        await gate.waitUntilSleeping(atLeast: 1)

        lifecycleSubject.send(.foregrounded)

        // No positive signal to await — yield generously and sample.
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(invocations == 1, "still-valid foreground should be a no-op, saw \(invocations) invocations")
    }

    @Test
    func nonForegroundLifecycleEventsAreIgnored() async throws {
        // Backgrounded/terminated/reachabilityChanged must not trigger the
        // foreground handler.
        let token = try makeJWT(issuedAt: refSeconds - 60, expiresAt: refSeconds + 3600)
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: lifecycle, clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            return token
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        lifecycleSubject.send(.backgrounded)
        lifecycleSubject.send(.terminated)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))

        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(invocations == 1, "non-foreground events must be ignored, saw \(invocations)")
    }

    @Test
    func foregroundWithExpiredCachedTokenClearsCacheAndRefetches() async throws {
        // iat=ref-60, exp=ref+31 → validates at the clock's start (ref < exp-30
        // = ref+1), but becomes stale the moment the clock crosses ref+1.
        // Advancing the clock to ref+2 makes the cached token expired; sending
        // .foregrounded then drives the "expired cached token" branch of
        // handleForegroundTransition, which clears the cache and refetches.
        let shortLivedToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 31,
            extraClaims: ["sub": "expiring"]
        )
        let freshToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "fresh"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: lifecycle, clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            return invocation == 1 ? shortLivedToken : freshToken
        }
        try await counter.waitFor(atLeast: 1)
        // shortLivedToken is now cached and its refresh armed.
        await gate.waitUntilSleeping(atLeast: 1)

        // Advance past the cached token's staleness threshold (exp - 30 = ref+1),
        // then foreground. The expired-cache branch clears the cache and eagerly
        // refetches (invocation 2 → freshToken), which caches and arms the next
        // refresh.
        clock.set(referenceDate.addingTimeInterval(2))
        lifecycleSubject.send(.foregrounded)

        try await counter.waitFor(atLeast: 2)
        await gate.waitUntilSleeping(atLeast: 2)

        let resolved = try await manager.currentToken(mode: .background)
        #expect(resolved == freshToken)
    }

    // MARK: - registerProvider cancellation

    @Test
    func registerProviderCancelsPriorScheduledRefresh() async throws {
        // Acquire a short-lived token whose refresh would fire at ref+10, then
        // immediately re-register with a long-lived token. Drive virtual time
        // past where the original refresh would have fired and release its
        // (now-cancelled) parked sleep; the original provider must not be called
        // a second time.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: noopLifecycle(), clock: clock, gate: gate)
        let firstCounter = CallCounter()
        let secondCounter = CallCounter()

        await manager.registerProvider {
            await firstCounter.increment()
            return firstToken
        }
        try await firstCounter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        await manager.registerProvider {
            await secondCounter.increment()
            return secondToken
        }
        try await secondCounter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 2)

        // Move past the original target (ref+10) and wake the oldest parked
        // sleep — that's the original schedule, which was cancelled by the
        // re-registration and must exit without refetching.
        clock.set(referenceDate.addingTimeInterval(40))
        await gate.release()
        for _ in 0..<100 {
            await Task.yield()
        }

        let firstInvocations = await firstCounter.value
        #expect(
            firstInvocations == 1,
            "original provider's scheduled refresh must have been cancelled, saw \(firstInvocations)"
        )
    }

    // MARK: - Refresh stream (refreshes())

    @Test
    func refreshesDeliversProactivelyRefreshedTokenToAllSubscribers() async throws {
        // Same timing as `refreshFiresAtScheduledTimeAndChainsNextSchedule`:
        // the refresh target lands at ref+10 (upper clamp = exp-30).
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: noopLifecycle(), clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            return invocation == 1 ? firstToken : secondToken
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        // Two independent subscribers, both attached before the refresh fires.
        let streamA = await manager.refreshes()
        let streamB = await manager.refreshes()

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()

        // Each subscriber's first delivered element must be the refreshed token.
        async let firstA = firstElement(of: streamA)
        async let firstB = firstElement(of: streamB)
        let (deliveredA, deliveredB) = await (firstA, firstB)

        #expect(deliveredA == secondToken)
        #expect(deliveredB == secondToken)
    }

    // MARK: - clearTokenState

    @Test
    func clearTokenStateDropsCachedTokenButRetainsProvider() async throws {
        // Warm the cache, then clear. The next fetch must re-invoke the
        // (retained) provider rather than serve a stale cache — observable by
        // returning a different token on the second invocation and seeing it
        // come back without any re-registration.
        let first = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "first"]
        )
        let second = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: noopLifecycle(), clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            return invocation == 1 ? first : second
        }

        let warm = try await manager.currentToken(mode: .background)
        #expect(warm == first)

        await manager.clearTokenState()

        let afterReset = try await manager.currentToken(mode: .background)
        #expect(
            afterReset == second,
            "cleared cache should re-fetch via the retained provider, not serve the old token"
        )
    }

    @Test
    func clearTokenStateCancelsScheduledRefresh() async throws {
        // Acquire a short-lived token whose refresh would fire at ref+10, then
        // immediately clear token state. Drive virtual time past where the
        // refresh would have fired and release its (now-cancelled) parked sleep;
        // the provider must not be called a second time.
        let token = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "first"]
        )

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: noopLifecycle(), clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            return token
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        await manager.clearTokenState()

        clock.set(referenceDate.addingTimeInterval(40))
        await gate.release()
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 1,
            "clearTokenState must cancel the scheduled refresh, saw \(invocations) invocations"
        )
    }

    @Test
    func refreshInFlightDuringResetDoesNotDeliverStaleToken() async throws {
        // A proactive refresh that is mid-flight when `clearTokenState()` runs
        // must not deliver the outgoing profile's token to live subscribers.
        //
        // This drives the realistic interleaving — reset lands while the
        // refresh fetch is suspended in the provider — which the in-flight
        // fetch cancellation in `clearTokenState()` covers. The
        // `cachedToken`-identity guard in `performScheduledRefresh()` hardens
        // the residual window where the fetch *completes* in the instant before
        // the send; that sub-window isn't deterministically reproducible in a
        // unit test, so it isn't asserted directly here.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: noopLifecycle(), clock: clock, gate: gate)
        let counter = CallCounter()
        let refreshStarted = Latch()
        let releaseRefresh = Latch()

        await manager.registerProvider {
            let invocation = await counter.increment()
            guard invocation >= 2 else { return firstToken }
            // Second invocation == the scheduled refresh. Park here so the test
            // can reset while this fetch is in flight.
            await refreshStarted.open()
            await releaseRefresh.wait()
            return secondToken
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        let collector = TokenCollector()
        let consumer = Task {
            for await token in await manager.refreshes() {
                await collector.append(token)
            }
        }

        // Fire the scheduled refresh: advance to the target and release the
        // parked sleep, which kicks off the second fetch.
        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()

        // Wait until the scheduled refresh has entered the provider, then reset
        // while it is suspended and let it return.
        await refreshStarted.wait()
        await manager.clearTokenState()
        await releaseRefresh.open()

        // No positive signal to await — yield generously so any erroneous send
        // would have propagated to the subscriber before we sample.
        for _ in 0..<200 {
            await Task.yield()
        }

        consumer.cancel()
        let delivered = await collector.received
        #expect(
            delivered.isEmpty,
            "a refresh interrupted by clearTokenState must deliver nothing, saw \(delivered)"
        )
    }

    // MARK: - Test helpers

    /// `referenceDate` as seconds-since-1970, for minting tokens whose `iat`/`exp`
    /// are expressed relative to the suite's fixed clock.
    private var refSeconds: TimeInterval {
        referenceDate.timeIntervalSince1970
    }

    /// Returns the first element a stream delivers (or `nil` if it finishes
    /// without delivering). Each call drives its own iterator, so independent
    /// subscribers can be awaited concurrently.
    private func firstElement(of stream: AsyncStream<String>) async -> String? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    /// Lifecycle source that emits nothing, for tests that don't exercise the
    /// foreground transition path. Uses an `Empty` publisher so the observer
    /// task simply parks on the await without ever firing.
    private func noopLifecycle() -> AppLifeCycleEvents {
        AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() })
    }

    /// Builds a manager driven by a deterministic clock and sleep gate.
    ///
    /// The manager's `currentDate` and `sleep` both default to real wall-clock
    /// sources (`environment.date` / `Task.sleep`). Tests inject a ``TestClock``
    /// and ``SleepGate`` instead so token validity, refresh scheduling, and
    /// refresh firing all advance in virtual time under the test's control —
    /// removing the real-time races that made these paths flaky on slow,
    /// parallel CI. Injecting also sidesteps the SDK-wide global `environment`,
    /// which sibling suites mutate concurrently under Swift Testing.
    private func makeManager(
        lifeCycle: AppLifeCycleEvents,
        clock: TestClock,
        gate: SleepGate
    ) -> AuthTokenManager {
        AuthTokenManager(
            lifeCycle: lifeCycle,
            currentDate: { clock.now() },
            sleep: { await gate.sleep($0) }
        )
    }
}
#endif
