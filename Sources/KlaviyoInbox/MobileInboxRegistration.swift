//
//  MobileInboxRegistration.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore

/// Turns Mobile Inbox capture on and off by writing the shared configuration file.
final class MobileInboxRegistration {
    static let groupPointerKey = "klaviyo.inbox.appGroupIdentifier"

    /// Replaced in tests. Production reads the real App Group and `UserDefaults.standard`.
    static var current = MobileInboxRegistration()

    private let group: InboxAppGroup
    private let defaults: UserDefaults

    init(group: InboxAppGroup = .system, defaults: UserDefaults = .standard) {
        self.group = group
        self.defaults = defaults
    }

    func register(_ configuration: MobileInboxConfig) {
        MobileInboxLogging.install()
        if let existing = defaults.string(forKey: Self.groupPointerKey),
           existing != configuration.appGroupIdentifier {
            InboxLog.error("App Group \(existing) is already registered for Mobile Inbox.")
        }
        let store = InboxConfigStore(appGroupIdentifier: configuration.appGroupIdentifier, group: group)
        do {
            try store.enable(localRetentionLimit: configuration.localRetentionLimit)
        } catch {
            InboxLog.error("registerForMobileInbox failed; Mobile Inbox stays off (\(error)).")
            return
        }
        defaults.set(configuration.appGroupIdentifier, forKey: Self.groupPointerKey)
    }

    /// `unregisterFromMobileInbox()` takes no arguments, so this looks up the App Group used at
    /// registration, which is kept in app-private `UserDefaults`.
    func unregister() {
        MobileInboxLogging.install()
        guard let appGroupIdentifier = defaults.string(forKey: Self.groupPointerKey) else {
            InboxLog.warning("unregisterFromMobileInbox called but Mobile Inbox was never registered.")
            return
        }
        do {
            try InboxConfigStore(appGroupIdentifier: appGroupIdentifier, group: group).disable()
        } catch {
            InboxLog.error("unregisterFromMobileInbox failed; Mobile Inbox may still be on (\(error)).")
        }
    }
}
