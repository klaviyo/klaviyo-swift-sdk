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

    @Test
    func foregroundRetriesAfterFailedScheduledRefresh() async throws {
        // Android parity (MAGE-629): a scheduled refresh that fires and *fails* while
        // the token is still valid must retry on the next foreground (case 2). The
        // token's target (ref+480) sits before its staleness threshold (exp-30 = ref+510).
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 540,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: lifecycle, clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2: throw URLError(.notConnectedToInternet) // scheduled refresh fails
            default: return secondToken // foreground-driven retry succeeds
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        let stream = await manager.refreshes()

        // Fire the refresh past its target; invocation 2 throws. Awaiting the armed
        // (but inert) connectivity wait signals the failure has settled.
        clock.set(referenceDate.addingTimeInterval(485))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        await awaitConnectivityWaitArmed(manager)

        // Foreground with the cache still valid but the target passed → case 2 retries.
        lifecycleSubject.send(.foregrounded)

        let delivered = await firstElement(of: stream)
        #expect(delivered == secondToken, "a failed scheduled refresh must be retried on foreground")

        let cached = try await manager.currentToken(mode: .background)
        #expect(cached == secondToken)

        let invocations = await counter.value
        #expect(
            invocations == 3,
            "expected initial + failed-scheduled + foreground-retry, saw \(invocations)"
        )
    }

    @Test
    func concurrentForegroundDuringInFlightScheduledRefreshBroadcastsOnce() async throws {
        // A foreground transition during an in-flight scheduled refresh must not lose
        // or duplicate its broadcast: case 2 leaves the running refresh alone (gated by
        // `activeScheduledRefreshID`), and it completes and broadcasts exactly once.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 540,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: lifecycle, clock: clock, gate: gate)
        let counter = CallCounter()
        let refreshStarted = Latch()
        let releaseRefresh = Latch()

        await manager.registerProvider {
            let invocation = await counter.increment()
            guard invocation >= 2 else { return firstToken }
            // Park the scheduled refresh in-flight so the foreground can race it.
            await refreshStarted.open()
            await releaseRefresh.wait()
            return secondToken
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        // Collect *every* emission, not just the first: a broken guard would let the
        // foreground also drive `performScheduledRefresh()`, and both callers awaiting
        // the shared fetch would broadcast — a duplicate that reading one element hides.
        // Subscribe up front (`refreshes()` installs its sink synchronously) so no
        // broadcast is missed; the stream buffers until the consumer drains it.
        let stream = await manager.refreshes()
        let collector = TokenCollector()
        let consumer = Task {
            for await token in stream {
                await collector.append(token)
            }
        }

        // Fire the refresh and wait until it is parked in-flight in the provider.
        clock.set(referenceDate.addingTimeInterval(485))
        await gate.release()
        await refreshStarted.wait()

        // Foreground while the refresh is parked: case 2 leaves it alone. Yield so the
        // handler runs before we release the fetch.
        lifecycleSubject.send(.foregrounded)
        for _ in 0..<100 {
            await Task.yield()
        }

        await releaseRefresh.open()

        // Suspend until the broadcast lands (a duplicate would have been buffered at the
        // same task completion), then drain and assert exactly one emission.
        await collector.waitFor(atLeast: 1)
        for _ in 0..<200 {
            await Task.yield()
        }
        consumer.cancel()

        let delivered = await collector.received
        #expect(
            delivered == [secondToken],
            "the in-flight refresh must broadcast exactly once despite the concurrent foreground, saw \(delivered)"
        )
        let invocations = await counter.value
        #expect(invocations == 2, "the in-flight fetch must be shared, not re-invoked, saw \(invocations)")
    }

    @Test
    func concurrentConnectivityRetryDuringForegroundRetryBroadcastsOnce() async throws {
        // A failed network refresh leaves `refreshAtWallClock` in the past *and* arms
        // the connectivity wait — so a foreground transition (case 2) and a reachability
        // event can both target the same still-armed refresh. The foreground retry parks
        // a fetch in-flight; the connectivity event must not start a second overlapping
        // `performScheduledRefresh` that awaits the shared fetch and broadcasts twice.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 540,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at arm so the failure doesn't kick the retry immediately; flipped
        // online below, after the foreground retry is parked in-flight.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()
        let refreshStarted = Latch()
        let releaseRefresh = Latch()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2: throw URLError(.notConnectedToInternet) // scheduled refresh fails offline
            default:
                // Foreground-driven retry: park in-flight so a reachability event races it.
                await refreshStarted.open()
                await releaseRefresh.wait()
                return secondToken
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        let stream = await manager.refreshes()
        let collector = TokenCollector()
        let consumer = Task {
            for await token in stream {
                await collector.append(token)
            }
        }

        // Fire the scheduled refresh: invocation 2 throws, arming the connectivity wait
        // (still offline). Await the arming so the foreground transition can't race it.
        clock.set(referenceDate.addingTimeInterval(485))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        await awaitConnectivityWaitArmed(manager)

        // Foreground with cache valid + target passed → case 2 starts the retry, which
        // parks in-flight with the connectivity wait still armed.
        lifecycleSubject.send(.foregrounded)
        await refreshStarted.wait()

        // Restore connectivity and fire the transition while the retry is parked: the
        // connectivity path must defer to the in-flight refresh, not start a second one.
        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        for _ in 0..<100 {
            await Task.yield()
        }

        await releaseRefresh.open()

        // Suspend until the broadcast lands (a duplicate would have been buffered at the
        // same task completion), then drain and assert exactly one emission.
        await collector.waitFor(atLeast: 1)
        for _ in 0..<200 {
            await Task.yield()
        }
        consumer.cancel()

        let delivered = await collector.received
        #expect(
            delivered == [secondToken],
            "concurrent foreground + connectivity retry must broadcast exactly once, saw \(delivered)"
        )
        let invocations = await counter.value
        #expect(invocations == 3, "the retry fetch must be shared, not re-invoked, saw \(invocations)")
    }

    @Test
    func foregroundAfterSuccessfulScheduledRefreshDoesNotRefire() async throws {
        // The flip side of keeping `refreshAtWallClock` set: a *succeeded* refresh
        // reschedules to a future target, so a later foreground falls through to
        // the still-valid no-op (case 3) rather than re-firing.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 540,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: lifecycle, clock: clock, gate: gate)
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            return invocation == 1 ? firstToken : secondToken
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        // Fire the refresh; invocation 2 succeeds and reschedules far in the future.
        clock.set(referenceDate.addingTimeInterval(485))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        await gate.waitUntilSleeping(atLeast: 2)

        // Foreground: cache fresh, replaced target far ahead → no-op.
        lifecycleSubject.send(.foregrounded)
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 2,
            "a succeeded scheduled refresh must not be re-fired on foreground, saw \(invocations)"
        )
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

    // MARK: - Connectivity-driven retry

    @Test
    func networkFailedRefreshRetriesWhenConnectivityRestored() async throws {
        // Same timing as the refresh-fires test: the refresh target lands at
        // ref+10. The scheduled refresh fails offline; the retry only fires once
        // reachability reports a path again — a `.notReachable` transition in the
        // meantime must be ignored.
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

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at arm so arming doesn't kick immediately; flipped online just
        // before the satisfied transition below.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2: throw URLError(.notConnectedToInternet) // scheduled refresh, offline
            default: return secondToken // connectivity-driven retry
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        // Subscribe before the retry so the broadcast can be observed.
        let stream = await manager.refreshes()

        // Fire the scheduled refresh: invocation 2 throws a network error, arming
        // the connectivity wait. Await the arming deterministically before driving
        // reachability so the transition can't race ahead of it.
        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        await awaitConnectivityWaitArmed(manager)

        // A change while still offline must not consume the armed wait — the
        // handler re-reads live status (`.notReachable`) and ignores it.
        lifecycleSubject.send(.reachabilityChanged(status: .notReachable))
        for _ in 0..<100 {
            await Task.yield()
        }
        let invocationsAfterUnreachable = await counter.value
        #expect(invocationsAfterUnreachable == 2, "a change while still offline must not trigger the retry")

        // Connectivity restored → retry fires (invocation 3), broadcasts and caches.
        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))

        let delivered = await firstElement(of: stream)
        #expect(delivered == secondToken)

        let cached = try await manager.currentToken(mode: .background)
        #expect(cached == secondToken)
    }

    @Test
    func armingWhileAlreadyOnlineRetriesWithoutWaitingForTransition() async throws {
        // If connectivity returned while the failing fetch was still in flight, the
        // `.reachabilityChanged` transition has already passed — only the arm-time
        // current-path check can kick the retry. No reachability event is sent here,
        // so recovery can only come from that check.
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
        // System reports a usable path throughout, and the lifecycle source emits
        // nothing — so only the arm-time check can drive the retry.
        let manager = makeManager(
            lifeCycle: noopLifecycle(),
            clock: clock,
            gate: gate,
            reachabilityStatus: { .reachableViaWiFi }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2: throw URLError(.notConnectedToInternet) // scheduled refresh fails offline...
            default: return secondToken // ...but the arm-time path check retries at once
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        let stream = await manager.refreshes()

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()

        let delivered = await firstElement(of: stream)
        #expect(
            delivered == secondToken,
            "an already-online arm must retry without waiting for a reachability transition"
        )
    }

    @Test
    func nonNetworkRefreshFailureDoesNotAwaitConnectivity() async throws {
        // A refresh failure that is *not* a network `URLError` must not arm the
        // connectivity wait — restoring connectivity wouldn't fix it. Note the
        // failure here is `ProviderTestError.network`: despite the name, it is not
        // a `URLError`, so it is correctly classified as non-connectivity.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "first"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Online throughout, so a satisfied transition *would* fire a retry if one
        // were armed — proving the absence is due to the failure not arming a wait.
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { .reachableViaWiFi }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            if invocation == 1 { return firstToken }
            throw ProviderTestError.network
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        try await counter.waitFor(atLeast: 2) // scheduled refresh failed (non-network)

        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 2,
            "a non-network failure must not arm a connectivity retry, saw \(invocations)"
        )
    }

    @Test
    func successfulFetchClearsPendingConnectivityWait() async throws {
        // A connectivity wait armed by a failed proactive refresh must be dropped
        // once a fresh token is acquired through *any other* path (here, a
        // `currentToken` fetch). Otherwise a later reachability transition would
        // fire a redundant retry against an already-fresh cache.
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

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at arm so arming doesn't immediately kick; flipped online before
        // the transition so the only thing suppressing the retry is the cleared wait.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2: throw URLError(.notConnectedToInternet) // proactive refresh fails offline → arms wait
            default: return secondToken // fresh token via another path (currentToken)
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        // Fire the scheduled refresh; it fails offline and arms the wait.
        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        await awaitConnectivityWaitArmed(manager)

        // A different path acquires a fresh token (firstToken is stale at ref+10),
        // which must clear the pending wait.
        let refreshed = try await manager.currentToken(mode: .background)
        #expect(refreshed == secondToken)

        // Connectivity later transitions to satisfied (and live status agrees). The
        // cache is already fresh and the wait was cleared, so no redundant retry
        // should fire.
        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 3,
            "a successful fetch must clear the pending connectivity wait, saw \(invocations)"
        )
    }

    @Test
    func clearTokenStateCancelsPendingConnectivityRetry() async throws {
        // Arm a connectivity wait via a network-failed refresh, then reset. The
        // pending wait must be dropped so a later reachability restoration does
        // not retry against the outgoing profile.
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

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at arm so arming doesn't immediately kick; flipped online before
        // the transition so the only thing suppressing the retry is the cancelled wait.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2: throw URLError(.notConnectedToInternet)
            default: return secondToken
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        // Ensure the wait is genuinely armed before clearing, so the test proves
        // clearTokenState *cancels* an armed wait rather than racing its arming.
        await awaitConnectivityWaitArmed(manager)

        await manager.clearTokenState()

        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 2,
            "clearTokenState must cancel the pending connectivity retry, saw \(invocations)"
        )
    }

    @Test
    func rapidReachableTransitionsTriggerSingleRetry() async throws {
        // The manager keeps at most one pending wait. A flurry of satisfied
        // transitions after a single network-failed refresh must produce exactly
        // one retry, not one per transition.
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

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at arm so arming doesn't immediately kick; flipped online before
        // the flurry so the transitions (not the arm-time check) drive the retry.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2: throw URLError(.notConnectedToInternet)
            default: return secondToken
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        await awaitConnectivityWaitArmed(manager)

        // Three satisfied transitions in quick succession. Only the first should
        // consume the armed wait; the rest find it already cleared.
        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWWAN))
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        try await counter.waitFor(atLeast: 3)
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 3,
            "rapid reachable transitions must yield a single retry, saw \(invocations)"
        )
    }

    @Test
    func failedRetryReArmsForNextConnectivityRestoration() async throws {
        // If the connectivity-driven retry itself fails for a network reason, the
        // wait is re-armed so the *next* restoration tries again.
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

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at arm so arming doesn't immediately kick; flipped online before
        // the restoration below.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            case 2, 3: throw URLError(.networkConnectionLost) // scheduled refresh + first retry
            default: return secondToken // second retry succeeds
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        await awaitConnectivityWaitArmed(manager)

        // Subscribe before restoring connectivity so the eventual success broadcast
        // is observable.
        let stream = await manager.refreshes()

        // Restore connectivity. The transition fires the retry (invocation 3),
        // which also fails — re-arming the wait. Because the path is still
        // satisfied, the re-armed wait retries again at once (invocation 4), which
        // succeeds and broadcasts. This exercises the re-arm-after-failure path.
        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))

        let delivered = await firstElement(of: stream)
        #expect(
            delivered == secondToken,
            "a network-failed retry must re-arm and recover"
        )
    }

    // MARK: - Initial-acquisition connectivity retry

    @Test
    func warmUpFetchFailureRetriesWhenConnectivityRestored() async throws {
        // Repro: the very FIRST token fetch (registerProvider's eager warm-up)
        // fails offline. Before the fix, nothing armed the connectivity wait
        // for this path, so restoring connectivity did nothing. After the
        // fix, `runFetch` itself arms the wait regardless of which caller drove
        // the failing fetch — no scheduled refresh ever ran here.
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at registration so the warm-up fetch fails; flipped online
        // just before the transition below.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            if invocation == 1 { throw URLError(.notConnectedToInternet) } // warm-up, offline
            return secondToken // connectivity-driven retry
        }
        try await counter.waitFor(atLeast: 1)
        await awaitConnectivityWaitArmed(manager)

        // Subscribe before restoring connectivity so the eventual broadcast is
        // observable.
        let stream = await manager.refreshes()

        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))

        let delivered = await firstElement(of: stream)
        #expect(delivered == secondToken, "an offline warm-up failure must retry once connectivity returns")

        let cached = try await manager.currentToken(mode: .background)
        #expect(cached == secondToken)
    }

    @Test
    func interactiveFetchFailureAlsoArmsConnectivityRetry() async throws {
        // Confirms the uniform-arming decision: an interactive (form-display)
        // fetch failure arms the wait exactly like the warm-up and
        // scheduled-refresh paths, since `runFetch` cannot distinguish its
        // caller and any connectivity failure there means the manager
        // currently has nothing cached to serve. Warms the cache via a normal
        // registration first, then clears it (retaining the provider) so a
        // subsequent *interactive* `currentToken(mode:)` call — not the
        // warm-up — is the one observing the failure.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken // warm-up succeeds
            case 2: throw URLError(.notConnectedToInternet) // interactive call, offline
            default: return secondToken // connectivity-driven retry
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1) // confirms warm-up cached firstToken

        await manager.clearTokenState() // drops cache, retains provider

        await #expect(throws: URLError.self) {
            _ = try await manager.currentToken(mode: .interactive)
        }
        await awaitConnectivityWaitArmed(manager)

        let stream = await manager.refreshes()
        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))

        let delivered = await firstElement(of: stream)
        #expect(delivered == secondToken, "an interactive fetch failure must retry once connectivity returns")
    }

    @Test
    func providerReplacedWhileFetchInFlightDoesNotArmStaleConnectivityRetry() async throws {
        // Same reentrancy race as `providerReplacedWhileFetchInFlightDoesNotPoisonCache`
        // (AuthTokenManagerTests.swift), but for the connectivity-retry arm rather
        // than the cache write. A stale fetch from a replaced provider that
        // eventually fails with a connectivity error must not arm the retry once
        // a newer fetch already succeeded — `runFetch`'s failure path guards on
        // the same `inFlight?.id == fetchID` generation check the success path
        // and the `defer` both rely on.
        //
        // Reachability is injected `.notReachable` (unlike the sibling cache
        // test, which uses the production initializer) so a spurious arm isn't
        // immediately self-consumed by `armConnectivityRetry`'s already-reachable
        // kick — that auto-consume would clear the flag regardless of whether
        // the generation guard actually held, masking the very regression this
        // test exists to catch. The final provider-invocation count is the
        // second, independent signal: a masked spurious arm would still drive an
        // extra fetch even if the flag read back `false` by the time we sample it.
        let lifecycle = noopLifecycle()
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let secondToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "second"]
        )

        let firstProviderEntered = Latch()
        let firstProviderRelease = Latch()

        await manager.registerProvider {
            await firstProviderEntered.open()
            await firstProviderRelease.wait()
            throw URLError(.notConnectedToInternet)
        }
        // Wait until the eager fetch has captured the first provider and is
        // suspended inside `provider()` — precondition for the reentrancy race.
        await firstProviderEntered.wait()

        // Swap in a new provider. The new eager fetch caches `secondToken`.
        let secondProviderCounter = CallCounter()
        await manager.registerProvider {
            await secondProviderCounter.increment()
            return secondToken
        }
        try await secondProviderCounter.waitFor(atLeast: 1)

        // Give the second (successful) fetch's completion time to land before
        // releasing the stale first provider.
        for _ in 0..<10 {
            await Task.yield()
        }

        // Release the stale first provider. Its in-flight fetch now throws a
        // connectivity-classified error — without the generation guard this
        // would arm a spurious retry even though the manager already has a
        // healthy cached token from the newer generation.
        await firstProviderRelease.open()

        for _ in 0..<10 {
            await Task.yield()
        }

        let isArmed = await manager.isAwaitingConnectivityRetryForTesting
        #expect(isArmed == false, "a stale fetch's failure must not arm a retry after a newer fetch already succeeded")

        let finalInvocations = await secondProviderCounter.value
        #expect(finalInvocations == 1, "a spurious retry would invoke the second provider again")

        let result = try await manager.currentToken(mode: .background)
        #expect(result == secondToken)
    }

    // MARK: - unregisterProvider

    @Test
    func unregisterProviderWhileIdleDropsProvider() async throws {
        // From a settled state — token cached, refresh scheduled, nothing in
        // flight — unregister must drop the provider and clear the cache, so the
        // next fetch throws `.noProviderRegistered` rather than serving a stale
        // token.
        let token = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
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
        // Refresh armed (and parked) ⇒ the eager fetch has settled into the cache.
        await gate.waitUntilSleeping(atLeast: 1)

        await manager.unregisterProvider()

        await #expect(throws: AuthTokenError.noProviderRegistered) {
            _ = try await manager.currentToken(mode: .background)
        }
    }

    @Test
    func unregisterProviderCancelsScheduledRefresh() async throws {
        // Acquire a short-lived token whose refresh would fire at ref+10, then
        // unregister. Drive virtual time past where the refresh would have fired
        // and release its (now-cancelled) parked sleep; the provider must not be
        // called again.
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

        await manager.unregisterProvider()

        clock.set(referenceDate.addingTimeInterval(40))
        await gate.release()
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 1,
            "unregisterProvider must cancel the scheduled refresh, saw \(invocations) invocations"
        )
    }

    @Test
    func unregisterProviderCancelsPendingConnectivityRetry() async throws {
        // Arm a connectivity wait via a network-failed refresh, then unregister.
        // The pending wait must be dropped so a later reachability restoration
        // does not retry against the detached provider.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 40,
            extraClaims: ["sub": "first"]
        )

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        // Offline at arm so arming doesn't immediately kick; flipped online before
        // the transition so the only thing suppressing the retry is the dropped wait.
        let reachability = TestReachability(.notReachable)
        let manager = makeManager(
            lifeCycle: lifecycle,
            clock: clock,
            gate: gate,
            reachabilityStatus: { reachability.status() }
        )
        let counter = CallCounter()

        await manager.registerProvider {
            let invocation = await counter.increment()
            switch invocation {
            case 1: return firstToken
            default: throw URLError(.notConnectedToInternet)
            }
        }
        try await counter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        clock.set(referenceDate.addingTimeInterval(10))
        await gate.release()
        try await counter.waitFor(atLeast: 2)
        // Ensure the wait is genuinely armed before unregistering, so the test
        // proves unregister *cancels* an armed wait rather than racing its arming.
        await awaitConnectivityWaitArmed(manager)

        await manager.unregisterProvider()

        reachability.set(.reachableViaWiFi)
        lifecycleSubject.send(.reachabilityChanged(status: .reachableViaWiFi))
        for _ in 0..<100 {
            await Task.yield()
        }

        let invocations = await counter.value
        #expect(
            invocations == 2,
            "unregisterProvider must cancel the pending connectivity retry, saw \(invocations)"
        )
    }

    @Test
    func unregisterProviderCancelsInFlightFetchForConcurrentCaller() async throws {
        // A caller dedup'd onto an in-flight fetch when unregister lands must not
        // receive a token — the cancelled fetch propagates a failure to it,
        // matching the established in-flight failure path.
        let token = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
            extraClaims: ["sub": "first"]
        )

        let clock = TestClock(referenceDate)
        let gate = SleepGate()
        let manager = makeManager(lifeCycle: noopLifecycle(), clock: clock, gate: gate)
        let counter = CallCounter()
        let providerEntered = Latch()
        let providerRelease = Latch()

        await manager.registerProvider {
            await counter.increment()
            await providerEntered.open()
            await providerRelease.wait()
            return token
        }
        // The eager fetch is now suspended inside the provider, so `inFlight` is
        // set and a concurrent caller will dedup onto it.
        await providerEntered.wait()

        // Unstructured task so the caller is not cancelled by the structured
        // scope when we unregister; it must fail via the in-flight fetch, not
        // its own cancellation.
        let dedupedCaller = Task { try await manager.currentToken(mode: .background) }
        // Let the caller reach the actor and dedup onto the in-flight fetch
        // before we unregister.
        for _ in 0..<50 {
            await Task.yield()
        }

        await manager.unregisterProvider()

        // Release the parked provider; the fetch's post-`provider()` cancellation
        // checkpoint trips (the closure itself ignores cancellation), failing the
        // shared task.
        await providerRelease.open()

        let callerResult = await dedupedCaller.result
        #expect(
            (try? callerResult.get()) == nil,
            "a caller dedup'd onto a fetch cancelled by unregister must not receive a token"
        )

        let invocations = await counter.value
        #expect(
            invocations == 1,
            "the concurrent caller must dedup, not start a second fetch; saw \(invocations)"
        )
    }

    @Test
    func reRegisterAfterUnregisterFetchesAndSchedulesAfresh() async throws {
        // After unregister, registering a new provider must behave like a clean
        // registration: eager fetch via the new provider and a fresh refresh
        // schedule.
        let firstToken = try makeJWT(
            issuedAt: refSeconds - 60,
            expiresAt: refSeconds + 3600,
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
        await manager.registerProvider {
            await firstCounter.increment()
            return firstToken
        }
        try await firstCounter.waitFor(atLeast: 1)
        await gate.waitUntilSleeping(atLeast: 1)

        await manager.unregisterProvider()

        // Re-register with a distinct provider. The eager fetch must run against
        // it (fresh invocation) and its token must be what the next call serves.
        let secondCounter = CallCounter()
        await manager.registerProvider {
            await secondCounter.increment()
            return secondToken
        }
        try await secondCounter.waitFor(atLeast: 1)
        // A fresh refresh is scheduled off the new token (second parked sleep).
        await gate.waitUntilSleeping(atLeast: 2)

        let result = try await manager.currentToken(mode: .background)
        #expect(
            result == secondToken,
            "re-registration must serve the new provider's token, not a stale one"
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

    /// Suspends until `manager` has armed its connectivity-retry wait, which lands
    /// asynchronously in the refresh-failure path — driving a transition before it
    /// would drop the event against an unarmed flag. Adapts to scheduling rather
    /// than guessing a yield count. The large cap is a safety net: if it's ever hit
    /// the wait never armed (a regression), and it records a labeled failure rather
    /// than spinning to CI's global timeout.
    private func awaitConnectivityWaitArmed(
        _ manager: AuthTokenManager,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let maxYields = 10_000
        for _ in 0..<maxYields {
            if await manager.isAwaitingConnectivityRetryForTesting { return }
            await Task.yield()
        }
        Issue.record("connectivity retry wait never armed", sourceLocation: sourceLocation)
    }

    /// Builds a manager driven by a deterministic clock and sleep gate.
    ///
    /// The manager's `currentDate` and `sleep` both default to real wall-clock
    /// sources (`environment.date` / `Task.sleep`). Tests inject a ``TestClock``
    /// and ``SleepGate`` instead so token validity, refresh scheduling, and
    /// refresh firing all advance in virtual time under the test's control —
    /// removing the real-time races that made these paths flaky on slow,
    /// parallel CI. Injecting also sidesteps the shared global `environment`
    /// clock (see ``TestClock`` for why that matters).
    private func makeManager(
        lifeCycle: AppLifeCycleEvents,
        clock: TestClock,
        gate: SleepGate,
        reachabilityStatus: @escaping () -> Reachability.NetworkStatus? = { nil }
    ) -> AuthTokenManager {
        AuthTokenManager(
            lifeCycle: lifeCycle,
            currentDate: { clock.now() },
            sleep: { await gate.sleep($0) },
            reachabilityStatus: reachabilityStatus
        )
    }
}
#endif
