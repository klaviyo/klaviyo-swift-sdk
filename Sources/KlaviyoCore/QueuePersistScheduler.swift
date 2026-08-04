//
//  QueuePersistScheduler.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/4/26.
//

import Foundation

/// A cancelable handle to work scheduled on a ``QueuePersistScheduler``.
public protocol QueuePersistToken {
    func cancel()
}

/// Timing seam for `QueueStore`'s debounced persistence. Injected so tests can drive
/// persistence deterministically without wall-clock delays.
public protocol QueuePersistScheduler {
    /// Run `work` after `delay` seconds. The returned token cancels it if not yet run.
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> QueuePersistToken
}

private struct DispatchWorkItemToken: QueuePersistToken {
    let item: DispatchWorkItem
    func cancel() { item.cancel() }
}

/// Production scheduler: a single serial queue so all writes are ordered.
public final class DispatchQueuePersistScheduler: QueuePersistScheduler {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = DispatchQueue(label: "com.klaviyo.queuestore.persist")) {
        self.queue = queue
    }

    public func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> QueuePersistToken {
        let item = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + delay, execute: item)
        return DispatchWorkItemToken(item: item)
    }
}
