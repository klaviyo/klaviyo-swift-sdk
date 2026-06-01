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

    // MARK: - Refresh fires (real-time, end-to-end)

    @Test
    func refreshFiresAtScheduledTimeAndChainsNextSchedule() async throws {
        // Token lifetime is chosen so the refresh target lands at the lower
        // clamp (now + 5s). The token must still validate against JWTParser,
        // which requires `now < exp - 30s`, so exp must be at least ~31s out.
        // exp=now+40 gives a ~10s validation window for test startup latency.
        // iat=now-60, exp=now+40 → 100s lifetime, ideal=now+30, upper=now+10,
        // lower=now+5 → max(now+5, min(now+30, now+10)) = now+10.
        let nowSeconds = Date().timeIntervalSince1970
        let firstToken = try makeJWT(
            issuedAt: nowSeconds - 60,
            expiresAt: nowSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(extraClaims: ["sub": "second"])

        let manager = makeManager(lifeCycle: noopLifecycle())
        let counter = CallCounter()
        let tokens = TokenBox(firstToken)

        await manager.registerProvider {
            await counter.increment()
            return await tokens.value
        }
        try await counter.waitFor(atLeast: 1)

        // Swap the provider's payload so we can observe the next fetch.
        await tokens.set(secondToken)

        // Scheduled refresh fires at ~now+10s. Wait for the second invocation.
        try await counter.waitFor(atLeast: 2)

        // The successful refresh wrote secondToken to the cache.
        let cached = try await manager.currentToken(mode: .background)
        #expect(cached == secondToken)
    }

    // MARK: - Foreground transitions

    @Test
    func foregroundWithStillValidTokenIsNoOp() async throws {
        // Hour-long token; foreground transition should be a no-op (refresh
        // is far in the future, cache is healthy). Assert by counting
        // provider invocations: exactly one (initial fetch) is expected.
        let validToken = try makeJWT()
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })

        let manager = makeManager(lifeCycle: lifecycle)
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            return validToken
        }
        try await counter.waitFor(atLeast: 1)

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
        let token = try makeJWT()
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })

        let manager = makeManager(lifeCycle: lifecycle)
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            return token
        }
        try await counter.waitFor(atLeast: 1)

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
        // Token lifetime is just barely past JWTParser's 30s leeway, so it
        // validates at acquisition but becomes "expired" (per
        // `isCachedTokenValid`) within a couple of real seconds.
        //
        // iat=now-60, exp=now+31 → validates if real wall time < exp-30 = now+1.
        // After sleeping ~2s, the cached token is stale. Sending .foregrounded
        // then drives the "expired cached token" branch of
        // handleForegroundTransition, which clears the cache and triggers an
        // eager fetch via the swapped TokenBox.
        let nowSeconds = Date().timeIntervalSince1970
        let shortLivedToken = try makeJWT(
            issuedAt: nowSeconds - 60,
            expiresAt: nowSeconds + 31,
            extraClaims: ["sub": "expiring"]
        )
        let freshToken = try makeJWT(extraClaims: ["sub": "fresh"])

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let lifecycle = AppLifeCycleEvents(lifeCycleEvents: { lifecycleSubject.eraseToAnyPublisher() })
        let manager = makeManager(lifeCycle: lifecycle)
        let counter = CallCounter()
        let tokens = TokenBox(shortLivedToken)

        await manager.registerProvider {
            await counter.increment()
            return await tokens.value
        }
        try await counter.waitFor(atLeast: 1)

        // Swap to a long-lived token and wait until the cached token has
        // crossed the staleness threshold.
        await tokens.set(freshToken)
        try await Task.sleep(nanoseconds: UInt64(2 * 1_000_000_000))

        lifecycleSubject.send(.foregrounded)
        try await counter.waitFor(atLeast: 2)

        let resolved = try await manager.currentToken(mode: .background)
        #expect(resolved == freshToken)
    }

    // MARK: - registerProvider cancellation

    @Test
    func registerProviderCancelsPriorScheduledRefresh() async throws {
        // Acquire a short-lived token whose refresh would fire at ~now+10s,
        // then immediately re-register with a long-lived token. Wait past
        // where the original refresh would have fired; the original provider
        // must not be called a second time.
        let nowSeconds = Date().timeIntervalSince1970
        let firstToken = try makeJWT(
            issuedAt: nowSeconds - 60,
            expiresAt: nowSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(extraClaims: ["sub": "second"])

        let manager = makeManager(lifeCycle: noopLifecycle())
        let firstCounter = CallCounter()
        let secondCounter = CallCounter()

        await manager.registerProvider {
            await firstCounter.increment()
            return firstToken
        }
        try await firstCounter.waitFor(atLeast: 1)

        await manager.registerProvider {
            await secondCounter.increment()
            return secondToken
        }
        try await secondCounter.waitFor(atLeast: 1)

        // Wait past where the original refresh would have fired (~now+10s).
        // The default proactive timeout (5s) and the original schedule's
        // lower-clamp (now+5s) are both below 12s, so 12s is safely past.
        try await Task.sleep(nanoseconds: UInt64(12 * 1_000_000_000))

        let firstInvocations = await firstCounter.value
        #expect(
            firstInvocations == 1,
            "original provider's scheduled refresh must have been cancelled, saw \(firstInvocations)"
        )
    }

    // MARK: - Refresh stream (refreshes())

    @Test
    func refreshesDeliversProactivelyRefreshedTokenToAllSubscribers() async throws {
        // Reuse the timing from `refreshFiresAtScheduledTimeAndChainsNextSchedule`:
        // the refresh target lands at ~now+10s (upper clamp = exp-30).
        let nowSeconds = Date().timeIntervalSince1970
        let firstToken = try makeJWT(
            issuedAt: nowSeconds - 60,
            expiresAt: nowSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(extraClaims: ["sub": "second"])

        let manager = makeManager(lifeCycle: noopLifecycle())
        let counter = CallCounter()
        let tokens = TokenBox(firstToken)

        await manager.registerProvider {
            await counter.increment()
            return await tokens.value
        }
        try await counter.waitFor(atLeast: 1)

        // Two independent subscribers, both attached before the refresh fires.
        let streamA = await manager.refreshes()
        let streamB = await manager.refreshes()

        await tokens.set(secondToken)

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
        // swapping the provider's output and seeing the new value come back
        // without any re-registration.
        let first = try makeJWT(extraClaims: ["sub": "first"])
        let second = try makeJWT(extraClaims: ["sub": "second"])
        let tokens = TokenBox(first)

        let manager = makeManager(lifeCycle: noopLifecycle())
        await manager.registerProvider { await tokens.value }

        let warm = try await manager.currentToken(mode: .background)
        #expect(warm == first)

        await tokens.set(second)
        await manager.clearTokenState()

        let afterReset = try await manager.currentToken(mode: .background)
        #expect(
            afterReset == second,
            "cleared cache should re-fetch via the retained provider, not serve the old token"
        )
    }

    @Test
    func clearTokenStateCancelsScheduledRefresh() async throws {
        // Acquire a short-lived token whose refresh would fire at ~now+10s,
        // then immediately clear token state. Wait past where the refresh would
        // have fired; the provider must not be called a second time.
        let nowSeconds = Date().timeIntervalSince1970
        let token = try makeJWT(
            issuedAt: nowSeconds - 60,
            expiresAt: nowSeconds + 40,
            extraClaims: ["sub": "first"]
        )

        let manager = makeManager(lifeCycle: noopLifecycle())
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            return token
        }
        try await counter.waitFor(atLeast: 1)

        await manager.clearTokenState()

        // Past the original schedule's ~now+10s target (and the 5s proactive
        // timeout), 12s is safely clear of where the refresh would have fired.
        try await Task.sleep(nanoseconds: UInt64(12 * 1_000_000_000))

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
        let nowSeconds = Date().timeIntervalSince1970
        let firstToken = try makeJWT(
            issuedAt: nowSeconds - 60,
            expiresAt: nowSeconds + 40,
            extraClaims: ["sub": "first"]
        )
        let secondToken = try makeJWT(extraClaims: ["sub": "second"])

        let manager = makeManager(lifeCycle: noopLifecycle())
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

        let collector = TokenCollector()
        let consumer = Task {
            for await token in await manager.refreshes() {
                await collector.append(token)
            }
        }

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

    /// Builds a manager pinned to the real wall-clock.
    ///
    /// The manager's `currentDate` defaults to the *global* `environment.date()`.
    /// Under Swift Testing's parallel execution, sibling XCTest suites set
    /// `environment = .test()`, whose clock is frozen to 2009
    /// (`Date(timeIntervalSince1970: 1_234_567_890)`). Tokens here are minted
    /// with real `Date()`, so a contaminated global clock leaves the manager
    /// ~17 years behind the tokens — making `sleepUntilAndRefresh`'s remaining
    /// duration astronomically large and the scheduled refresh effectively
    /// never fire. Injecting the real clock keeps the manager's time source
    /// consistent with the tokens and immune to that cross-suite mutation.
    private func makeManager(lifeCycle: AppLifeCycleEvents) -> AuthTokenManager {
        AuthTokenManager(lifeCycle: lifeCycle, currentDate: { Date() })
    }
}
#endif
