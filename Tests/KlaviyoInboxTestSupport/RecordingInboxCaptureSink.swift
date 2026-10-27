//
//  RecordingInboxCaptureSink.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore

/// Records every record it is handed and answers with a fixed result. Safe to read from any thread.
package final class RecordingInboxCaptureSink: InboxCaptureSink {
    private let lock = NSLock()
    private var storage: [InboxRecord] = []
    private var storedResult: InboxCaptureResult

    package init(result: InboxCaptureResult = .captured) {
        storedResult = result
    }

    package var records: [InboxRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    package func capture(_ record: InboxRecord) async -> InboxCaptureResult {
        lock.lock()
        defer { lock.unlock() }
        storage.append(record)
        return storedResult
    }
}
