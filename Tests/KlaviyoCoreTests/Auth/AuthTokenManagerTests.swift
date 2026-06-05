//
//  AuthTokenManagerTests.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct AuthTokenManagerTests {
    // MARK: - currentToken: provider absence

    @Test
    func currentTokenWithoutProviderThrowsNoProviderRegistered() async {
        let manager = AuthTokenManager()

        await #expect(throws: AuthTokenError.noProviderRegistered) {
            _ = try await manager.currentToken()
        }
    }

    // MARK: - currentToken: happy path

    @Test
    func currentTokenInvokesProviderAndReturnsTokenString() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()

        await manager.registerProvider { token }
        let result = try await manager.currentToken()

        #expect(result == token)
    }

    @Test
    func currentTokenServesCachedTokenOnSubsequentCalls() async throws {
        let manager = AuthTokenManager()
        let initialToken = try makeJWT()
        let swappedToken = try makeJWT(extraClaims: ["sub": "user-after-swap"])
        let providerToken = TokenBox(initialToken)

        await manager.registerProvider {
            await providerToken.value
        }

        // Warm the cache deterministically: awaiting an explicit fetch
        // guarantees the actor has parsed and cached `initialToken` before we
        // mutate the provider's return value below.
        let warmup = try await manager.currentToken()
        #expect(warmup == initialToken)

        // Swap the provider's output without re-registering (which would
        // clear the cache). If the cache is honored, subsequent calls keep
        // returning `initialToken`; if they re-invoke the provider, they
        // observe `swappedToken`.
        await providerToken.set(swappedToken)

        let first = try await manager.currentToken()
        let second = try await manager.currentToken()

        #expect(first == initialToken, "cached token should be served, not the swapped provider output")
        #expect(second == initialToken, "cached token should be served, not the swapped provider output")
    }

    // MARK: - currentToken: provider errors

    @Test
    func currentTokenRethrowsErrorFromProvider() async throws {
        let manager = AuthTokenManager()

        await manager.registerProvider {
            throw ProviderTestError.network
        }

        await #expect(throws: ProviderTestError.network) {
            _ = try await manager.currentToken()
        }
    }

    @Test
    func currentTokenThrowsValidationFailedForMalformedToken() async {
        let manager = AuthTokenManager()

        await manager.registerProvider { "not.a.valid.jwt" }

        await #expect(throws: AuthTokenError.validationFailed(.malformedStructure)) {
            _ = try await manager.currentToken()
        }
    }

    @Test
    func currentTokenThrowsValidationFailedForExpiredToken() async throws {
        // Pin the manager to a fixed clock so acquisition-time validation
        // doesn't depend on the SDK-wide `environment.date` (see `TestClock`
        // for why the global clock is unsafe here). The token expired an hour
        // before that fixed instant.
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredToken = try makeJWT(
            issuedAt: fixedNow.timeIntervalSince1970 - 3660,
            expiresAt: fixedNow.timeIntervalSince1970 - 3600
        )
        let manager = AuthTokenManager(currentDate: { fixedNow })

        await manager.registerProvider { expiredToken }

        await #expect(throws: AuthTokenError.validationFailed(.expiredOnReceipt)) {
            _ = try await manager.currentToken()
        }
    }

    // MARK: - registerProvider behaviors

    @Test
    func registerProviderEagerlyFetches() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            return token
        }

        try await counter.waitFor(atLeast: 1)
        let count = await counter.value
        #expect(count >= 1)
    }

    @Test
    func replacingProviderDiscardsCachedToken() async throws {
        let manager = AuthTokenManager()
        let firstToken = try makeJWT()
        let secondToken = try makeJWT(extraClaims: ["sub": "user-2"])

        let firstCounter = CallCounter()
        await manager.registerProvider {
            await firstCounter.increment()
            return firstToken
        }
        try await firstCounter.waitFor(atLeast: 1)
        let firstResult = try await manager.currentToken()
        #expect(firstResult == firstToken)

        // Swap the provider — the cached firstToken should be discarded, so the
        // next currentToken() call must consult the new provider.
        let secondCounter = CallCounter()
        await manager.registerProvider {
            await secondCounter.increment()
            return secondToken
        }
        try await secondCounter.waitFor(atLeast: 1)
        let secondResult = try await manager.currentToken()
        #expect(secondResult == secondToken)
    }

    // MARK: - currentToken: concurrent-caller deduplication

    @Test
    func concurrentCallersShareSingleProviderInvocation() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()
        let counter = CallCounter()
        let providerEntered = Latch()
        let providerRelease = Latch()

        await manager.registerProvider {
            await counter.increment()
            await providerEntered.open()
            await providerRelease.wait()
            return token
        }
        // Wait for the eager fetch to enter the provider so that subsequent
        // currentToken() calls find an in-flight fetch and dedup with it.
        await providerEntered.wait()

        // Spawn 8 concurrent callers. They should all observe the in-flight
        // fetch and `await` it rather than starting their own.
        let callerCount = 8
        async let results: [String] = withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<callerCount {
                group.addTask {
                    try await manager.currentToken(mode: .background)
                }
            }
            var collected: [String] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        // Release the provider so the in-flight fetch can complete and all
        // dedup'd awaiters can resume.
        await providerRelease.open()

        let allResults = try await results
        #expect(allResults.count == callerCount)
        #expect(allResults.allSatisfy { $0 == token })

        let invocations = await counter.value
        #expect(
            invocations == 1,
            "exactly one provider invocation expected across \(callerCount) concurrent callers + eager fetch"
        )
    }

    // MARK: - currentToken: timeout enforcement

    @Test
    func interactiveTimeoutThrowsWithinBudget() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()
        let releaseFetch = Latch()

        await manager.registerProvider {
            // Park the fetch so it cannot complete during the timeout window.
            // The only way `currentToken` can return is via the timeout firing,
            // which makes the assertion immune to scheduler starvation — no
            // wall-clock bound needed (a `Task.sleep` can be delayed arbitrarily
            // on a loaded CI runner, but a parked fetch never wins the race).
            await releaseFetch.wait()
            return token
        }

        await #expect(throws: AuthTokenError.timedOut) {
            _ = try await manager.currentToken(mode: .interactive)
        }

        // Let the parked fetch unwind.
        await releaseFetch.open()
    }

    @Test
    func backgroundTimeoutThrowsWithinBudget() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()
        let releaseFetch = Latch()

        await manager.registerProvider {
            // Park the fetch so only the timeout can resolve the call. See
            // `interactiveTimeoutThrowsWithinBudget` for why this avoids a
            // wall-clock assertion.
            await releaseFetch.wait()
            return token
        }

        await #expect(throws: AuthTokenError.timedOut) {
            _ = try await manager.currentToken(mode: .background)
        }

        await releaseFetch.open()
    }

    @Test
    func interactiveTimeoutLeavesFetchTaskRunningForLaterCallers() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()
        let counter = CallCounter()
        let releaseFetch = Latch()

        await manager.registerProvider {
            await counter.increment()
            // Park so the interactive caller is forced to time out while this
            // fetch is still in flight (rather than racing a real sleep against
            // the budget, which can reorder under CI starvation).
            await releaseFetch.wait()
            return token
        }

        // First caller bails out via the interactive timeout while the shared
        // fetch is still parked (and, critically, not cancelled).
        await #expect(throws: AuthTokenError.timedOut) {
            _ = try await manager.currentToken(mode: .interactive)
        }

        // A background caller arriving now must dedup onto that same still-in-
        // flight fetch rather than triggering a second provider call.
        async let later = manager.currentToken(mode: .background)
        await releaseFetch.open()
        let result = try await later
        #expect(result == token)

        let invocations = await counter.value
        // Eager fetch + the dedup'd call should sum to a single invocation.
        // (If the interactive timeout had killed the underlying fetch, we'd
        // see a second invocation here.)
        #expect(
            invocations == 1,
            "interactive timeout must not cancel the shared in-flight fetch; saw \(invocations) invocations"
        )
    }

    // MARK: - currentToken: failure recovery

    @Test
    func failureClearsInFlightSoNextCallReinvokesProvider() async throws {
        let manager = AuthTokenManager()
        let counter = CallCounter()
        let successToken = try makeJWT()
        // Single stateful provider on a single manager: it fails until we flip
        // `behavior`, then succeeds. Crucially we never re-register (that would
        // reset `inFlight` itself and make the test prove nothing).
        let behavior = ProviderBehavior(failing: true)

        await manager.registerProvider {
            await counter.increment()
            if await behavior.isFailing {
                throw ProviderTestError.network
            }
            return successToken
        }

        // Phase 1 — drive a failure through the public API. Awaiting the fetch
        // task to completion guarantees `runFetch`'s `defer` has cleared
        // `inFlight` by the time this returns: `Task.value` resolves only after
        // the task body (defers included) fully unwinds. This call either
        // dedups with the eager warm fetch or starts its own — either way it
        // throws and the slot it awaited is cleared.
        await #expect(throws: ProviderTestError.network) {
            _ = try await manager.currentToken(mode: .background)
        }
        let failingInvocations = await counter.value
        #expect(failingInvocations >= 1)

        // Phase 2 — flip the provider to succeed (no re-registration). If the
        // failed fetch had left a stale `inFlight`, this call would re-await the
        // dead task and throw `.network` instead of starting a fresh fetch.
        await behavior.stopFailing()

        let result = try await manager.currentToken(mode: .background)
        #expect(result == successToken)

        // The success required a *new* provider invocation, which only happens
        // if the post-failure `defer` cleared `inFlight`.
        let recoveredInvocations = await counter.value
        #expect(recoveredInvocations > failingInvocations)
    }

    // MARK: - currentToken: cache integrity across provider swap

    @Test
    func providerReplacedWhileFetchInFlightDoesNotPoisonCache() async throws {
        // Regression test: actor reentrancy at the `await provider()` call in
        // the in-flight fetch previously allowed a stale fetch from a replaced
        // provider to write its (now-stale) token back into the cache after the
        // new provider had already cached its own token. The fix relies on
        // cancellation: `registerProvider(_:)` cancels the in-flight task, and
        // the fetch body's explicit `Task.checkCancellation()` checkpoint drops
        // the stale write on the floor even when the host's provider closure
        // does not honor cancellation.
        let manager = AuthTokenManager()
        let firstToken = try makeJWT(extraClaims: ["sub": "user-a"])
        let secondToken = try makeJWT(extraClaims: ["sub": "user-b"])

        let firstProviderEntered = Latch()
        let firstProviderRelease = Latch()

        await manager.registerProvider {
            await firstProviderEntered.open()
            await firstProviderRelease.wait()
            return firstToken
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

        // Release the first provider. Its in-flight fetch returns
        // `firstToken`; without cancellation safety it would overwrite the
        // cache.
        await firstProviderRelease.open()

        // Yield so the resumed continuation has time to run before we sample
        // the cache.
        for _ in 0..<10 {
            await Task.yield()
        }

        let result = try await manager.currentToken(mode: .background)
        #expect(result == secondToken)
    }
}

// MARK: - Test helpers

extension AuthTokenManagerTests {
    /// One-way switch read by a stateful provider so its behavior can flip from
    /// failing to succeeding across invocations *without* re-registering — which
    /// would reset the in-flight slot and cache and defeat tests that exercise
    /// post-failure recovery on a single manager.
    actor ProviderBehavior {
        private(set) var isFailing: Bool

        init(failing: Bool) {
            isFailing = failing
        }

        func stopFailing() {
            isFailing = false
        }
    }
}
#endif
