//
//  AuthTokenTestHelpers.swift
//  KlaviyoFormsTests
//

import Foundation
import KlaviyoCore

func makeFormsJWT(subject: String) throws -> String {
    let now = environment.date().timeIntervalSince1970
    let payload = try JSONSerialization.data(withJSONObject: [
        "sub": subject,
        "iat": now - 60,
        "exp": now + 3600
    ])
    return [Data("{}".utf8), payload, Data(subject.utf8)]
        .map { data in
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        .joined(separator: ".")
}

actor FormsTokenSource {
    private(set) var value: String

    init(_ value: String) {
        self.value = value
    }

    func set(_ value: String) {
        self.value = value
    }
}

actor FormsTestGate {
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
