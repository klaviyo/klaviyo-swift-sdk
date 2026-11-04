//
//  RecordingInboxChangeSignal.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation
import KlaviyoInboxCore

/// Counts posts instead of sending them, so a test can assert whether a store signalled a change.
package final class RecordingInboxChangeSignal: InboxChangeSignaling, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    package init() {}

    package var postCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    package func post() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
