//
//  OnceCallback.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/29/26.
//

import Foundation

/// Wraps a callback so it fires at most once, regardless of how many callers invoke it.
///
/// Used in `UNUserNotificationCenterDelegate` proxy methods to ensure a completion
/// handler is called exactly once even when both the proxy and a forwarded host delegate
/// each attempt to invoke it.
///
/// Thread-safe: the first concurrent caller wins; all subsequent calls are no-ops.
final class OnceCallback<Input>: @unchecked Sendable {
    private var body: ((Input) -> Void)?
    private let lock = NSLock()

    init(_ body: @escaping (Input) -> Void) {
        self.body = body
    }

    func callAsFunction(_ input: Input) {
        lock.lock()
        let cb = body
        body = nil
        lock.unlock()
        cb?(input)
    }
}

extension OnceCallback where Input == Void {
    func callAsFunction() {
        callAsFunction(())
    }
}
