//
//  BadJWTTestHelpers.swift
//  klaviyo-swift-sdk
//
//  Shared fixtures for `.badJWT` handling tests: JWT minting and deterministic
//  provider-invocation counting.
//

import Foundation

/// Builds a JWT with `iat` slightly in the past and `exp` an hour ahead so it
/// passes `JWTParser` validation in the present. Signature is a placeholder —
/// `AuthTokenManager` never validates it.
func makeTestJWT() throws -> String {
    let nowSeconds = Date().timeIntervalSince1970
    let payload: [String: Any] = [
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
