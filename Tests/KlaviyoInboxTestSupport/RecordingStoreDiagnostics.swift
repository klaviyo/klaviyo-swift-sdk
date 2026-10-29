//
//  RecordingStoreDiagnostics.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore

/// Collects the events an `InboxStore` reports. Safe to use from any thread.
package final class RecordingStoreDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [InboxStoreEvent] = []

    package init() {}

    package var events: [InboxStoreEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    package func record(_ event: InboxStoreEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }

    package var hasDegraded: Bool {
        events.contains { if case .degraded = $0 { return true } else { return false } }
    }

    package var hasRecovered: Bool {
        events.contains { if case .recovered = $0 { return true } else { return false } }
    }
}
