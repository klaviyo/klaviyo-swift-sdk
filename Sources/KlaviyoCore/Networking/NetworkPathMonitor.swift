//
//  NetworkPathMonitor.swift
//  klaviyo-swift-sdk
//

import Foundation
import Network

/// A source of network path updates. `NWPathMonitor` is the production conformance; tests inject a
/// fake that delivers statuses directly, since `NWPath` can't be constructed.
protocol NetworkPathSource: AnyObject {
    /// Begins delivering updates on `queue`. Called at most once per instance.
    func start(queue: DispatchQueue, onUpdate: @escaping @Sendable (Reachability.NetworkStatus) -> Void)
    /// Stops delivering updates. The instance can't be restarted afterwards.
    func cancel()
}

extension NWPathMonitor: NetworkPathSource {
    func start(queue: DispatchQueue, onUpdate: @escaping @Sendable (Reachability.NetworkStatus) -> Void) {
        pathUpdateHandler = { path in onUpdate(Reachability.NetworkStatus(path: path)) }
        start(queue: queue)
    }
}

/// Tracks the device's network path and posts ``ReachabilityChangedNotification`` when the mapped
/// ``Reachability/NetworkStatus`` changes.
///
/// A cancelled `NWPathMonitor` can't be restarted, so every ``start()`` after a ``stop()`` builds a
/// fresh source. Updates from a source that has since been stopped or replaced are dropped, and
/// repeated updates with an unchanged status are de-duplicated. The last status survives
/// ``stop()``, so restarting only posts if the status changed in the meantime.
///
/// `@unchecked Sendable` is sound: all mutable state is guarded by `lock`.
final class NetworkPathMonitor: @unchecked Sendable {
    private let lock = UnfairLock()
    private let queue = DispatchQueue(label: "com.klaviyo.network-path-monitor")
    private let notificationCenter: NotificationCenter
    private let makeSource: () -> NetworkPathSource

    private var activeSource: NetworkPathSource?
    private var lastStatus: Reachability.NetworkStatus?

    init(
        notificationCenter: NotificationCenter = .default,
        makeSource: @escaping () -> NetworkPathSource = { NWPathMonitor() }
    ) {
        self.notificationCenter = notificationCenter
        self.makeSource = makeSource
    }

    /// The most recent status the monitor observed, or `nil` before the first path update.
    var currentStatus: Reachability.NetworkStatus? {
        lock.withLock { lastStatus }
    }

    /// Starts monitoring with a fresh source. A no-op while already running.
    func start() {
        let source: NetworkPathSource? = lock.withLock {
            guard activeSource == nil else { return nil }
            let source = makeSource()
            activeSource = source
            return source
        }
        source?.start(queue: queue) { [weak self, weak source] status in
            guard let self, let source else { return }
            self.receive(status, from: source)
        }
    }

    /// Stops monitoring and discards the current source.
    func stop() {
        let source: NetworkPathSource? = lock.withLock {
            defer { activeSource = nil }
            return activeSource
        }
        source?.cancel()
    }

    private func receive(_ status: Reachability.NetworkStatus, from source: NetworkPathSource) {
        let changed = lock.withLock { () -> Bool in
            guard source === activeSource, status != lastStatus else { return false }
            lastStatus = status
            return true
        }
        if changed {
            notificationCenter.post(name: ReachabilityChangedNotification, object: self)
        }
    }
}
