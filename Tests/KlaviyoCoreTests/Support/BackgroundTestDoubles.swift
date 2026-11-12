//
//  BackgroundTestDoubles.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Foundation

/// A clock whose sleeps park until the test fires them, so a per-send budget never expires by accident.
final class ManualSleepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [Int: CheckedContinuation<Void, Error>] = [:]
    private var nextId = 0
    private var _requested: [TimeInterval] = []

    var requested: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return _requested }

    var clock: SleepClock {
        SleepClock { [self] seconds in
            let id = register(seconds)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    lock.lock()
                    if Task.isCancelled {
                        lock.unlock()
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters[id] = continuation
                        lock.unlock()
                    }
                }
            } onCancel: {
                cancelWaiter(id)
            }
        }
    }

    private func register(_ seconds: TimeInterval) -> Int {
        lock.lock(); defer { lock.unlock() }
        nextId += 1
        _requested.append(seconds)
        return nextId
    }

    private func cancelWaiter(_ id: Int) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()
        waiter?.resume(throwing: CancellationError())
    }

    /// Completes every parked sleep normally (the budget "elapses").
    func fireAll() {
        lock.lock()
        let all = waiters
        waiters = [:]
        lock.unlock()
        all.values.forEach { $0.resume() }
    }

    func waitForRequested(atLeast count: Int, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if requested.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return requested.count >= count
    }
}

/// Stands in for `UIApplication.beginBackgroundTask`: counts begins and ends, and lets a test expire
/// the task by hand (the handler runs, then the task ends, as in production).
final class FakeBackgroundTasks: @unchecked Sendable {
    private let lock = NSLock()
    private var _begins = 0
    private var _ends = 0
    private var expiries: [@Sendable () -> Void] = []
    private var handles: [BackgroundTaskHandle] = []
    var deny = false

    var begins: Int { lock.lock(); defer { lock.unlock() }; return _begins }
    var ends: Int { lock.lock(); defer { lock.unlock() }; return _ends }

    var runner: BackgroundTaskRunner {
        BackgroundTaskRunner { [self] _, onExpire in
            lock.lock()
            if deny {
                lock.unlock()
                return nil
            }
            _begins += 1
            let handle = BackgroundTaskHandle { [self] in
                lock.lock(); _ends += 1; lock.unlock()
            }
            expiries.append(onExpire)
            handles.append(handle)
            lock.unlock()
            return handle
        }
    }

    /// Fires the latest task's expiry handler and ends it, like the system deadline.
    func expire() {
        lock.lock()
        let expiry = expiries.last
        let handle = handles.last
        lock.unlock()
        expiry?()
        handle?.end()
    }
}
