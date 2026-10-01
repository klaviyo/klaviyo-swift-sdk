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
func makeTestJWT(subject: String? = nil, validAt date: Date = Date()) throws -> String {
    let seconds = date.timeIntervalSince1970
    var payload: [String: Any] = ["iat": seconds - 60, "exp": seconds + 3600]
    if let subject { payload["sub"] = subject }
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

actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
