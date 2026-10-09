//
//  InboxLogRecorder.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore
import os

/// Captures `InboxLog` output for the lifetime of the recorder. Safe to read from any thread.
package final class InboxLogRecorder {
    package struct Entry: Equatable {
        package let type: OSLogType
        package let message: String
    }

    private let lock = NSLock()
    private var storage: [Entry] = []

    package init() {
        InboxLog.recorder = { [weak self] type, message in
            self?.append(Entry(type: type, message: message))
        }
    }

    deinit {
        InboxLog.recorder = nil
    }

    package var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    package var errors: [Entry] { entries.filter { $0.type == .error } }
    package var warnings: [Entry] { entries.filter { $0.type == .default } }

    private func append(_ entry: Entry) {
        lock.lock()
        storage.append(entry)
        lock.unlock()
    }
}
