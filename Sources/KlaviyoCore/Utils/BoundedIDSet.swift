//
//  BoundedIDSet.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 6/1/26.
//

import Foundation

/// A bounded, FIFO-evicting set of unique identifiers.
///
/// Tracks membership up to `capacity` entries. Once full, the oldest entry is
/// evicted before a new one is inserted. Inserting a duplicate ID is a no-op
/// and does not affect the eviction order.
///
/// Typical use: deduplicating events or operations identified by a `Hashable`
/// key within a single process lifetime (e.g. preventing double-tracking of
/// push-open events when both an automatic proxy and a manual call fire for
/// the same notification).
///
/// Entries live for the process lifetime; only FIFO overflow or an explicit
/// `clear()` removes them.
///
/// Thread-safe: `NSLock` serialises all mutations and lookups.
package final class BoundedIDSet<ID: Hashable>: @unchecked Sendable {
    let capacity: Int

    private var ids: Set<ID> = []
    private var order: [ID] = []
    private let lock = NSLock()

    package init(capacity: Int = 256) {
        self.capacity = capacity
    }

    package func insert(_ id: ID) {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.contains(id) else { return }
        if ids.count >= capacity, let oldest = order.first {
            ids.remove(oldest)
            order.removeFirst()
        }
        ids.insert(id)
        order.append(id)
    }

    package func contains(_ id: ID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(id)
    }

    package func clear() {
        lock.lock()
        defer { lock.unlock() }
        ids.removeAll()
        order.removeAll()
    }
}
