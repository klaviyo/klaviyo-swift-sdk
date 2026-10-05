//
//  PreInitMemoryBuffer.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/17/26.
//

import Foundation

/// Non-durable, process-local sink for the pre-init calls worth preserving without disk capture:
/// high-priority events (push-opens) and the latest push token. Held only until `initialize()`
/// drains it, lost on process death. Used only when `featureFlags.enablePreInitDiskCapture` is false.
/// Not persisted — no disk I/O.
final class PreInitMemoryBuffer {
    static let shared = PreInitMemoryBuffer()
    static let maxBufferSize = 200

    private let lock = UnfairLock()
    private var requests: [UnattributedRequest] = []

    /// Appends a request, coalescing push tokens to the latest and evicting the oldest when at
    /// capacity (FIFO drop-oldest).
    func append(_ request: UnattributedRequest) {
        let didEvict = lock.withLock { () -> Bool in
            // Coalesce: a new token supersedes any earlier buffered token (keep latest only).
            if case .pushToken = request {
                requests.removeAll {
                    if case .pushToken = $0 { return true }
                    return false
                }
            }
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

    /// Rewrites `previousAnonymousId` to `replacementAnonymousId` in every buffered request's
    /// `anonymousId` (see `UnattributedBuffer`).
    func remapAnonymousId(from previousAnonymousId: String, to replacementAnonymousId: String) {
        lock.withLock {
            requests = requests.map {
                $0.replacingAnonymousId(previousAnonymousId, with: replacementAnonymousId)
            }
        }
    }

    func reset() {
        lock.withLock {
            requests = []
        }
    }
}
