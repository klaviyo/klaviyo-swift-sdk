//
//  ForwardingCycleGuard.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/30/26.
//

import Foundation

/// Tracks in-flight notification request identifiers to detect and break delegate forwarding cycles.
///
/// When two `UNUserNotificationCenterDelegate` objects each forward to the other, every callback
/// recurses until the stack overflows. One `ForwardingCycleGuard` instance per callback type
/// (e.g. `didReceive`, `willPresent`) breaks the cycle: `begin` returns `false` on re-entry
/// for the same request ID, signalling the caller to skip forwarding.
///
/// Thread-safe: `NSLock` serialises the check-and-insert so concurrent callers on different
/// threads cannot both pass the guard for the same ID.
final class ForwardingCycleGuard: @unchecked Sendable {
    private var activeIds: Set<String> = []
    private let lock = NSLock()

    /// Returns `true` and records `id` if it is not already in flight; `false` if it is.
    func begin(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !activeIds.contains(id) else { return false }
        activeIds.insert(id)
        return true
    }

    /// Removes `id` from the in-flight set, allowing a future `begin` to succeed.
    func end(_ id: String) {
        lock.lock()
        activeIds.remove(id)
        lock.unlock()
    }
}
