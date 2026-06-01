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
        let manager = AuthTokenManager()
        let past = Date().timeIntervalSince1970 - 3600
        let expiredToken = try makeJWT(issuedAt: past - 60, expiresAt: past)

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

        await manager.registerProvider {
            // Sleep well past the interactive budget so the timeout always wins.
            try await Task.sleep(nanoseconds: UInt64(2 * 1_000_000_000))
            return token
        }

        let start = Date()
        await #expect(throws: AuthTokenError.timedOut) {
            _ = try await manager.currentToken(mode: .interactive)
        }
        let elapsed = Date().timeIntervalSince(start)
        // Allow generous headroom for CI scheduler jitter; the assertion that
        // matters is "did not wait the full provider duration (2s)".
        #expect(elapsed < 1.5, "interactive caller should time out near 500ms, took \(elapsed)s")
    }

    @Test
    func backgroundTimeoutThrowsWithinBudget() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()

        await manager.registerProvider {
            // Sleep well past the background budget so the timeout always wins.
            try await Task.sleep(nanoseconds: UInt64(10 * 1_000_000_000))
            return token
        }

        let start = Date()
        await #expect(throws: AuthTokenError.timedOut) {
            _ = try await manager.currentToken(mode: .background)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 8.0, "background caller should time out near 5s, took \(elapsed)s")
    }

    @Test
    func interactiveTimeoutLeavesFetchTaskRunningForLaterCallers() async throws {
        let manager = AuthTokenManager()
        let token = try makeJWT()
        let counter = CallCounter()

        await manager.registerProvider {
            await counter.increment()
            // Sleep longer than the interactive budget but well under the background budget.
            try await Task.sleep(nanoseconds: UInt64(800 * 1_000_000))
            return token
        }

        // First caller bails out via the interactive timeout.
        await #expect(throws: AuthTokenError.timedOut) {
            _ = try await manager.currentToken(mode: .interactive)
        }

        // The in-flight fetch should still be running — a background caller
        // should dedup with it rather than triggering a second provider call.
        let result = try await manager.currentToken(mode: .background)
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
    /// One-shot async gate. `wait()` suspends until `open()` is called; once
    /// open it stays open. Used to interleave a provider's resumption with
    /// other operations in deterministic order.
    actor Latch {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            guard !isOpen else { return }
            isOpen = true
            for waiter in waiters {
                waiter.resume()
            }
            waiters.removeAll()
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// Counts provider invocations and lets tests await a specific call count
    /// without sleeping. `signal` runs every increment so any waiters can wake up
    /// promptly when their threshold is met.
    actor CallCounter {
        private(set) var value = 0
        private var waiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

        func increment() {
            value += 1
            waiters = waiters.compactMap { waiter in
                if value >= waiter.threshold {
                    waiter.continuation.resume()
                    return nil
                }
                return waiter
            }
        }

        func waitFor(atLeast threshold: Int) async throws {
            if value >= threshold { return }
            await withCheckedContinuation { continuation in
                waiters.append((threshold, continuation))
            }
        }
    }

    /// Mutable token holder used to change a registered provider's return
    /// value over time without re-registering (re-registration would clear
    /// the cache and defeat tests that depend on a warm cache).
    actor TokenBox {
        private(set) var value: String

        init(_ initial: String) {
            value = initial
        }

        func set(_ new: String) {
            value = new
        }
    }

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

    enum ProviderTestError: Error, Equatable {
        case network
    }

    /// Builds a JWT with default `iat` slightly in the past and `exp` an hour
    /// ahead so it passes ``JWTParser`` validation in the present.
    fileprivate func makeJWT(
        issuedAt: TimeInterval? = nil,
        expiresAt: TimeInterval? = nil,
        extraClaims: [String: Any] = [:]
    ) throws -> String {
        let nowSeconds = Date().timeIntervalSince1970
        let issuedAtSeconds = issuedAt ?? (nowSeconds - 60)
        let expiresAtSeconds = expiresAt ?? (nowSeconds + 3600)

        var payload: [String: Any] = extraClaims
        payload["iat"] = issuedAtSeconds
        payload["exp"] = expiresAtSeconds

        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let headerSeg = try base64URLEncode(JSONSerialization.data(withJSONObject: header))
        let payloadSeg = try base64URLEncode(JSONSerialization.data(withJSONObject: payload))
        return "\(headerSeg).\(payloadSeg).signature"
    }

    fileprivate func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif
