//
//  ForwardingCycleGuard.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/30/26.
//

import Foundation

/// Tracks in-flight notification request identifiers to detect delegate forwarding cycles
/// and hand back the re-entry depth so callers can advance through an ordered delegate chain.
///
/// When two `UNUserNotificationCenterDelegate` objects each forward to the other (e.g. Klaviyo's
/// proxy forwards to a third-party proxy, which forwards back to Klaviyo), a naive begin/end
/// Boolean guard breaks the cycle but also discards the third-party proxy's own forwarding step.
/// Tracking re-entry depth instead lets `KlaviyoNotificationDelegate` select the *next* delegate
/// in its chain on each re-entrant call, rather than short-circuiting to an empty result.
///
/// Thread-safe: `NSLock` serialises the check-and-increment so concurrent callers on different
/// threads cannot race on the same ID's depth.
final class ForwardingCycleGuard: @unchecked Sendable {
    private var activeDepths: [String: Int] = [:]
    private let lock = NSLock()

    /// Records one more level of re-entry for `id` and returns the zero-based depth
    /// this call occupies (0 for the first/outermost call, 1 for the first re-entrant
    /// call forwarded back into the same request, and so on).
    func enter(_ id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let depth = activeDepths[id, default: 0]
        activeDepths[id] = depth + 1
        return depth
    }

    /// Unwinds one level of re-entry for `id`, clearing it entirely once the outermost
    /// call also leaves.
    func leave(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = activeDepths[id, default: 1] - 1
        if remaining <= 0 {
            activeDepths[id] = nil
        } else {
            activeDepths[id] = remaining
        }
    }
}
