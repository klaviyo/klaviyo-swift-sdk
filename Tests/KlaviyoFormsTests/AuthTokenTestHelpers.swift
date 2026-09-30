//
//  AuthTokenTestHelpers.swift
//  klaviyo-swift-sdk
//
//  Shared fixtures for Forms auth token tests: JWT minting and deterministic
//  provider coordination.
//

import Foundation

/// Builds a JWT with `iat` slightly in the past and `exp` an hour ahead so it
/// passes `JWTParser` validation in the present. `subject` keeps tokens minted in
/// the same second distinct. Signature is a placeholder — `AuthTokenManager`
/// never validates it.
func makeTestJWT(subject: String = "test") throws -> String {
    let nowSeconds = Date().timeIntervalSince1970
    let payload: [String: Any] = [
        "sub": subject,
        "iat": nowSeconds - 60,
        "exp": nowSeconds + 3600
    ]
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

/// Counts provider invocations and lets tests await a specific call count
/// without sleeping.
actor InvocationCounter {
    private(set) var value = 0
    private var waiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    @discardableResult
    func increment() -> Int {
        value += 1
        waiters = waiters.compactMap { waiter in
            if value >= waiter.threshold {
                waiter.continuation.resume()
                return nil
            }
            return waiter
        }
        return value
    }

    func waitFor(atLeast threshold: Int) async {
        if value >= threshold { return }
        await withCheckedContinuation { continuation in
            waiters.append((threshold, continuation))
        }
    }
}

/// One-shot async gate. ``wait()`` suspends until ``open()`` is called; once
/// open it stays open.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

enum TestProviderError: Error {
    case failed
}
