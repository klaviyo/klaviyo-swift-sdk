//
//  LifecycleState.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/14/26.
//

import Combine
import Foundation
import KlaviyoCore

/// The SDK's session-scoped initialization state machine.
///
/// `uninitialized → initializing → initialized` is the only legal forward path.
/// `reset()` returns the holder to `.uninitialized` for test isolation.
///
/// - Important: This state is **never persisted**. Each cold-start begins `.uninitialized`
///   so that the migration pass, UnattributedBuffer drain, and lifecycle `start()` always
///   run exactly once per process lifetime.
enum InitializationState: Equatable {
    case uninitialized
    case initializing
    case initialized
}

/// Thread-safe holder for the SDK's lifecycle `InitializationState`.
///
/// Concurrency invariant: `lock` is a non-recursive `NSLock`. `subject.send` delivers
/// synchronously to Combine subscribers, so we NEVER call it while holding `lock`
/// (a subscriber re-entering any lock-guarded accessor would deadlock). Instead, each
/// mutating method captures the next state under the lock, then emits outside it.
///
/// Seeding `subject` from `init` is safe: no subscribers exist yet.
final class LifecycleState {
    // MARK: - Shared singleton

    /// Process-lifetime shared instance. Later tasks wire SDK entry points to this instance.
    static let shared = LifecycleState()

    // MARK: - Private storage

    private let lock = NSLock()

    /// Canonical state, guarded by `lock`.
    private var value: InitializationState

    /// Broadcast channel. Only read or mutated **outside** `lock`.
    private let subject: CurrentValueSubject<InitializationState, Never>

    // MARK: - Init

    init(_ initial: InitializationState = .uninitialized) {
        value = initial
        subject = CurrentValueSubject(initial)
    }

    // MARK: - Public interface

    var current: InitializationState { lock.withLock { value } }

    var publisher: AnyPublisher<InitializationState, Never> { subject.eraseToAnyPublisher() }

    /// Transitions `.uninitialized → .initializing`.
    ///
    /// - Returns: `true` if the transition occurred; `false` if the state was already past
    ///   `.uninitialized` (idempotent guard).
    @discardableResult
    func beginInitializing() -> Bool {
        let transitioned: Bool = lock.withLock {
            guard value == .uninitialized else { return false }
            value = .initializing
            return true
        }
        if transitioned {
            subject.send(.initializing)
        }
        return transitioned
    }

    /// Transitions `.initializing → .initialized`. No-op if not currently `.initializing`.
    ///
    /// - Returns: `true` if the transition occurred (this caller won the race);
    ///   `false` if the state was already past `.initializing` (idempotent guard).
    @discardableResult
    func completeInitialization() -> Bool {
        let transitioned: Bool = lock.withLock {
            guard value == .initializing else { return false }
            value = .initialized
            return true
        }
        if transitioned { subject.send(.initialized) }
        return transitioned
    }

    /// Resets to `.uninitialized`. Intended for test isolation only.
    package func reset() {
        lock.withLock { value = .uninitialized }
        SessionState.markUninitialized()
        subject.send(.uninitialized)
    }
}
