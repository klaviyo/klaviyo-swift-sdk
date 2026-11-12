//
//  BackgroundTaskRunner.swift
//  klaviyo-swift-sdk
//

import Foundation
import UIKit

/// A begun background task. `end()` is idempotent and safe from any thread.
public final class BackgroundTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var endAction: (() -> Void)?

    public init(end: (() -> Void)? = nil) {
        endAction = end
    }

    /// Installs the action that ends the task. Used where the action needs the system-issued id.
    func setEnd(_ action: @escaping () -> Void) {
        lock.lock()
        endAction = action
        lock.unlock()
    }

    public func end() {
        lock.lock()
        let action = endAction
        endAction = nil
        lock.unlock()
        action?()
    }
}

/// Seam over `UIApplication.beginBackgroundTask` so the queue never touches `UIApplication` directly
/// and tests can drive expiry by hand. Keep this off any code path an app extension can reach.
public struct BackgroundTaskRunner: Sendable {
    /// Begins a background task, or returns `nil` when the system denies it. `onExpire` runs
    /// synchronously on the system's expiry thread, and the task is ended right after it returns.
    public var begin: @Sendable (_ name: String, _ onExpire: @escaping @Sendable () -> Void) async
        -> BackgroundTaskHandle?

    public init(
        begin: @escaping @Sendable (String, @escaping @Sendable () -> Void) async -> BackgroundTaskHandle?
    ) {
        self.begin = begin
    }

    public static let production = BackgroundTaskRunner { name, onExpire in
        await MainActor.run { () -> BackgroundTaskHandle? in
            let handle = BackgroundTaskHandle()
            let id = UIApplication.shared.beginBackgroundTask(withName: name) {
                // Main thread, system deadline: flag the owner, then end without any further hop.
                onExpire()
                handle.end()
            }
            guard id != .invalid else { return nil }
            handle.setEnd {
                if Thread.isMainThread {
                    UIApplication.shared.endBackgroundTask(id)
                } else {
                    DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(id) }
                }
            }
            return handle
        }
    }
}
