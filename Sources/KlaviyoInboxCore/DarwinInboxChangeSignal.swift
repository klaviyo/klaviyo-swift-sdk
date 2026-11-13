//
//  DarwinInboxChangeSignal.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation

/// The cross-process change signal: a Darwin notification named after the App Group, so the app and
/// the Notification Service Extension hear each other and no other app does. It carries no payload;
/// a listener refetches what it is showing. A suspended app misses a post, so a host also refetches
/// when it returns to the foreground.
package struct DarwinInboxChangeSignal: InboxChangeSignaling {
    package static let namePrefix = "com.klaviyo.inbox.changed."

    private let appGroup: InboxAppGroup

    package init(appGroup: InboxAppGroup = .system) {
        self.appGroup = appGroup
    }

    /// Nil when the App Group identifier is missing, in which case there is no one to signal.
    private var name: CFNotificationName? {
        appGroup.identifier().map { CFNotificationName((Self.namePrefix + $0) as CFString) }
    }

    package func post() {
        guard let name else { return }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true
        )
    }

    /// One element per post from any process sharing the App Group. Finishing the stream, or dropping
    /// it, removes the observer.
    package func changes() -> AsyncStream<Void> {
        guard let name else { return AsyncStream { $0.finish() } }
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = Observer(name: name) { continuation.yield() }
            continuation.onTermination = { _ in observer.remove() }
        }
    }
}

/// Owns one Darwin observer registration. The callback runs on whatever thread Darwin delivers on.
private final class Observer {
    private let name: CFNotificationName
    private let onChange: () -> Void

    init(name: CFNotificationName, onChange: @escaping () -> Void) {
        self.name = name
        self.onChange = onChange
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().onChange()
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
    }

    func remove() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            name,
            nil
        )
    }
}
