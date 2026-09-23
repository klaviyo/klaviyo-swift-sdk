//
//  AuthTokenTestHelpers.swift
//  KlaviyoSwiftTests
//

import Foundation
import KlaviyoCore

func makeAuthJWT(subject: String) throws -> String {
    let now = environment.date().timeIntervalSince1970
    let payload = try JSONSerialization.data(withJSONObject: [
        "sub": subject,
        "iat": now - 60,
        "exp": now + 3600
    ])
    return [Data("{}".utf8), payload, Data(subject.utf8)]
        .map(base64URLEncode)
        .joined(separator: ".")
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

actor AuthTestGate {
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

actor CompanyTokenSource {
    private let firstToken: String
    private let nextToken: String
    private let firstCallEntered: AuthTestGate
    private let releaseFirstCall: AuthTestGate
    private var invocationCount = 0

    init(
        firstToken: String,
        nextToken: String,
        firstCallEntered: AuthTestGate,
        releaseFirstCall: AuthTestGate
    ) {
        self.firstToken = firstToken
        self.nextToken = nextToken
        self.firstCallEntered = firstCallEntered
        self.releaseFirstCall = releaseFirstCall
    }

    func token() async -> String {
        invocationCount += 1
        if invocationCount == 1 {
            await firstCallEntered.open()
            await releaseFirstCall.wait()
            return firstToken
        }
        return nextToken
    }
}
