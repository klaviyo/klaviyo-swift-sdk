//
//  AuthTokenTestHelpers.swift
//  klaviyo-swift-sdk
//
//  Shared fixtures for identity-change auth-token tests: a manually-advanced clock,
//  a gated refresh sleep, and a scriptable token provider.
//

import Foundation

/// Manually-advanced clock with a synchronously-readable `now`, injected as an
/// `AuthTokenManager`'s `currentDate`.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date()) {
        current = start
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// Gated stand-in for an `AuthTokenManager`'s `sleep`. Every ``sleep(_:)`` records its
/// entry and parks until ``release()``, so a scheduled refresh fires only when the test
/// advances the clock past its target and releases the parked sleep. Sleeps left parked
/// at test end never resume.
actor SleepGate {
    private var enteredCount = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var pendingReleases = 0
    private var entryWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Injected as the manager's `sleep` closure. The duration is ignored.
    func sleep(_: UInt64) async {
        enteredCount += 1
        entryWaiters = entryWaiters.filter { waiter in
            guard enteredCount >= waiter.threshold else { return true }
            waiter.continuation.resume()
            return false
        }
        if pendingReleases > 0 {
            pendingReleases -= 1
            return
        }
        await withCheckedContinuation { parked.append($0) }
    }

    /// Suspends until at least `threshold` sleeps have been entered.
    func waitUntilSleeping(atLeast threshold: Int = 1) async {
        if enteredCount >= threshold { return }
        await withCheckedContinuation { entryWaiters.append((threshold, $0)) }
    }

    /// Wakes the oldest parked sleep, or lets the next ``sleep(_:)`` return at once if
    /// none is parked yet.
    func release() {
        if parked.isEmpty {
            pendingReleases += 1
        } else {
            parked.removeFirst().resume()
        }
    }
}

enum ScriptedTokenProviderError: Error {
    case scriptedFailure
}

/// Token provider fixture. Each invocation mints a distinct token valid at the
/// supplied `currentDate`. Invocations passed to ``hold(invocation:)`` suspend until
/// the returned latch opens or their task is cancelled, then return their token either
/// way. Invocations passed to ``fail(invocation:)`` throw instead of returning.
actor ScriptedTokenProvider {
    private let currentDate: @Sendable () -> Date
    private let invocations = InvocationCounter()
    private(set) var invocationCount = 0
    private var minted: [Int: String] = [:]
    private var holds: [Int: Latch] = [:]
    private var failures: Set<Int> = []
    private var cancelled: Set<Int> = []
    private var cancellationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.currentDate = currentDate
    }

    /// Makes invocation number `invocation` (1-based) wait for the returned latch, or for
    /// its task to be cancelled, before returning its token.
    func hold(invocation: Int) -> Latch {
        let latch = Latch()
        holds[invocation] = latch
        return latch
    }

    /// Makes invocation number `invocation` (1-based) throw
    /// ``ScriptedTokenProviderError/scriptedFailure``.
    func fail(invocation: Int) {
        failures.insert(invocation)
    }

    /// The token minted by invocation number `invocation` (1-based), once it has run.
    func token(_ invocation: Int) -> String? {
        minted[invocation]
    }

    func waitFor(invocations threshold: Int) async {
        await invocations.waitFor(atLeast: threshold)
    }

    /// Suspends until held invocation number `invocation` has been cancelled.
    func waitForCancellation(invocation: Int) async {
        if cancelled.contains(invocation) { return }
        await withCheckedContinuation { cancellationWaiters[invocation, default: []].append($0) }
    }

    func provide() async throws -> String {
        invocationCount += 1
        let invocation = invocationCount
        let token = try makeTestJWT(subject: "token-\(invocation)", validAt: currentDate())
        minted[invocation] = token
        let latch = holds[invocation]
        await invocations.increment()
        if let latch {
            await withTaskCancellationHandler {
                await latch.wait()
            } onCancel: {
                Task { await latch.open() }
            }
            if Task.isCancelled {
                markCancelled(invocation)
            }
        }
        if failures.contains(invocation) {
            throw ScriptedTokenProviderError.scriptedFailure
        }
        return token
    }

    private func markCancelled(_ invocation: Int) {
        cancelled.insert(invocation)
        cancellationWaiters.removeValue(forKey: invocation)?.forEach { $0.resume() }
    }
}
