//
//  AuthTestHelpers.swift
//  KlaviyoCore
//
//  Shared fixtures for ``AuthTokenManager`` test suites: JWT minting,
//  deterministic clock injection, and async-coordination primitives.
//

@testable import KlaviyoCore
import Foundation

// MARK: - JWT minting

/// Builds a JWT with default `iat` slightly in the past and `exp` an hour
/// ahead so it passes ``JWTParser`` validation in the present.
func makeJWT(
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

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// MARK: - Concurrency primitives

/// One-shot async gate. ``wait()`` suspends until ``open()`` is called; once
/// open it stays open. Used to interleave a provider's resumption with other
/// operations in deterministic order.
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
/// without sleeping. Every increment resumes any waiters whose threshold the
/// new value has reached, so tests block only as long as necessary.
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

/// Mutable token holder used to change a registered provider's return value
/// over time without re-registering (re-registration would clear the cache
/// and defeat tests that depend on a warm cache).
actor TokenBox {
    private(set) var value: String

    init(_ initial: String) {
        value = initial
    }

    func set(_ token: String) {
        value = token
    }
}

enum ProviderTestError: Error, Equatable {
    case network
}
