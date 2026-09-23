//
//  PreInitMemoryBuffer.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/17/26.
//

import Foundation

/// Non-durable, process-local sink for high-priority pre-init calls (push-opens). Mirrors Android's
/// in-memory `preInitQueue`: held only until `initialize()` drains it, lost on process death. Used
/// only when `featureFlags.enablePreInitDiskCapture` is false. Not persisted — no disk I/O.
final class PreInitMemoryBuffer {
    static let shared = PreInitMemoryBuffer()
    static let maxBufferSize = 200

    private let lock = UnfairLock()
    private var requests: [UnattributedRequest] = []

    /// Appends a request, evicting the oldest when at capacity (FIFO drop-oldest).
    func append(_ request: UnattributedRequest) {
        let didEvict = lock.withLock { () -> Bool in
            let evicting = requests.count >= Self.maxBufferSize
            if evicting {
                requests.removeFirst()
            }
            requests.append(request)
            return evicting
        }
        if didEvict {
            environment.emitDeveloperWarning(
                "PreInitMemoryBuffer full (\(Self.maxBufferSize)); dropping oldest pre-init request")
        }
    }

    /// Returns the buffered requests in FIFO order and clears the buffer.
    func drain() -> [UnattributedRequest] {
        lock.withLock {
            let snapshot = requests
            requests = []
            return snapshot
        }
    }

    func reset() {
        lock.withLock {
            requests = []
        }
    }
}
