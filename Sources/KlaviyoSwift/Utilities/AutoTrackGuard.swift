//
//  AutoTrackGuard.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 6/1/26.
//

import Foundation

/// Tracks request identifiers that have already been auto-tracked by the Klaviyo proxy
/// delegate, so a subsequent manual `handle(notificationResponse:)` call can short-circuit
/// and avoid firing a duplicate `Opened Push` event.
///
/// Bounded at `capacity` entries with FIFO eviction — in practice a host would need to
/// tap hundreds of push notifications between app foregrounding cycles to reach the cap.
///
/// Thread-safe: `NSLock` serialises all mutations and lookups.
final class AutoTrackGuard: @unchecked Sendable {
    static let capacity = 256

    private var ids: Set<String> = []
    private var order: [String] = []
    private let lock = NSLock()

    func markTracked(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.contains(id) else { return }
        if ids.count >= Self.capacity, let oldest = order.first {
            ids.remove(oldest)
            order.removeFirst()
        }
        ids.insert(id)
        order.append(id)
    }

    func wasTracked(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(id)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        ids.removeAll()
        order.removeAll()
    }
}
