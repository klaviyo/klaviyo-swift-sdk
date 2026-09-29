//
//  AuthTokenCommandQueue.swift
//  KlaviyoCore
//

import Foundation

package final class AuthProfileResetTransition: @unchecked Sendable, Equatable {
    private actor Phase {
        private var isComplete = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isComplete { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func complete() {
            guard !isComplete else { return }
            isComplete = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    private let id = UUID()
    private let authClearPhase = Phase()
    private let profileResetPhase = Phase()

    package static func ==(lhs: AuthProfileResetTransition, rhs: AuthProfileResetTransition) -> Bool {
        lhs.id == rhs.id
    }

    package init() {}

    package func waitForAuthClear() async {
        await authClearPhase.wait()
    }

    package func completeAuthClear() async {
        await authClearPhase.complete()
    }

    package func waitForProfileReset() async {
        await profileResetPhase.wait()
    }

    package func completeProfileReset() async {
        await profileResetPhase.complete()
    }
}

package final class AuthTokenCommandQueue: @unchecked Sendable {
    package enum Command: Sendable {
        case clearTokenState
        case clearTokenStateAfter(Task<Void, Never>)
        case profileReset(AuthProfileResetTransition, @Sendable () async -> Void)
        case register(AuthTokenProvider)
        case unregister
    }

    package static let shared = AuthTokenCommandQueue(manager: .shared)

    private let manager: AuthTokenManager
    private let lock = NSLock()
    private var tail: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var pendingProfileResets: [AuthProfileResetTransition] = []

    package var revision: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return sequence
    }

    package init(manager: AuthTokenManager) {
        self.manager = manager
    }

    @discardableResult
    package func enqueue(_ command: Command) -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }
        return enqueueLocked(command)
    }

    package func companyTransitionFence() -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let pendingReset = pendingProfileResets.last {
            return Task { await pendingReset.waitForAuthClear() }
        }
        return enqueueLocked(.clearTokenState)
    }

    private func enqueueLocked(_ command: Command) -> Task<Void, Never> {
        let previous = tail
        let manager = manager
        if case let .profileReset(transition, _) = command {
            pendingProfileResets.append(transition)
        }
        let task = Task {
            await previous?.value
            switch command {
            case .clearTokenState:
                await manager.clearTokenState()
            case let .clearTokenStateAfter(profileReset):
                await profileReset.value
                await manager.clearTokenState()
            case let .profileReset(transition, dispatch):
                await manager.clearTokenState()
                await transition.completeAuthClear()
                await dispatch()
                await transition.waitForProfileReset()
                finishProfileReset(transition)
            case let .register(provider):
                await manager.registerProvider(provider)
            case .unregister:
                await manager.unregisterProvider()
            }
        }
        tail = task
        sequence &+= 1
        return task
    }

    private func finishProfileReset(_ transition: AuthProfileResetTransition) {
        lock.lock()
        pendingProfileResets.removeAll { $0 == transition }
        lock.unlock()
    }

    @discardableResult
    package func waitForPendingCommands(onSnapshot: @Sendable () -> Void = {}) async -> UInt64? {
        let (pending, snapshotRevision) = pendingCommand()
        onSnapshot()
        await pending?.value
        return revision == snapshotRevision ? snapshotRevision : nil
    }

    private func pendingCommand() -> (Task<Void, Never>?, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (tail, sequence)
    }
}
