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
}

// MARK: - Test helpers

extension AuthTokenManagerTests {
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
