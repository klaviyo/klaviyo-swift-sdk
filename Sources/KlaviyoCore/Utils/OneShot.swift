//
//  OneShot.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Resolves exactly once, from any thread. Lets an `await` return as soon as the first of several
/// racers finishes, without waiting on work that ignores cancellation (the iOS 13/14 `dataTask` path).
final class OneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var stored: T?
    private var continuation: CheckedContinuation<T, Never>?

    /// First call wins; later calls are ignored.
    func finish(_ value: T) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            stored = value
            lock.unlock()
        }
    }

    func wait() async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            lock.lock()
            if done, let value = stored {
                stored = nil
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}
