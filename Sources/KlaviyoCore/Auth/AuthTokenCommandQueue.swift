//
//  AuthTokenCommandQueue.swift
//  KlaviyoCore
//

import Foundation

package final class AuthTokenCommandQueue: @unchecked Sendable {
    package enum Command: Sendable {
        case clearTokenState
        case register(AuthTokenProvider)
        case unregister
    }

    package static let shared = AuthTokenCommandQueue(manager: .shared)

    private let manager: AuthTokenManager
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    package init(manager: AuthTokenManager) {
        self.manager = manager
    }

    @discardableResult
    package func enqueue(_ command: Command) -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }

        let previous = tail
        let manager = manager
        let task = Task {
            await previous?.value
            switch command {
            case .clearTokenState:
                await manager.clearTokenState()
            case let .register(provider):
                await manager.registerProvider(provider)
            case .unregister:
                await manager.unregisterProvider()
            }
        }
        tail = task
        return task
    }

    package func waitForPendingCommands() async {
        let pending = pendingCommand()
        await pending?.value
    }

    private func pendingCommand() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        let pending = tail
        return pending
    }
}
