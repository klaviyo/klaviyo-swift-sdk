//
//  MobileInboxRegistration.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore

/// Turns Mobile Inbox capture on and off by writing the shared configuration file.
///
/// `unregisterFromMobileInbox()` takes no arguments, so the group used at registration is
/// remembered in app-private `UserDefaults` and read back by `unregister()`, including after a relaunch.
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
        if let previous = defaults.string(forKey: Self.groupPointerKey),
           previous != configuration.appGroupIdentifier {
            InboxLog.warning(
                "App Group changed from \(previous) to \(configuration.appGroupIdentifier). " +
                    "Changing it after registering isn't supported; \(previous) is not turned off."
            )
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
