//
//  AuthTokenCommandQueue.swift
//  KlaviyoCore
//

import Foundation

package final class AuthTokenCommandQueue: @unchecked Sendable {
    package enum Command: Sendable {
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
        lock.lock()
        let pending = tail
        lock.unlock()
        await pending?.value
    }
}
