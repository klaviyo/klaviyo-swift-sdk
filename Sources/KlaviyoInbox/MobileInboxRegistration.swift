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
        guard disablePreviousGroup(unless: configuration.appGroupIdentifier) else { return }
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

    /// Turns off the group remembered from an earlier registration when the app switches groups, so
    /// `unregister()` (which only knows the latest group) can't leave the earlier one capturing.
    /// An unreachable earlier group is already unreadable, so it doesn't block the new registration.
    /// Returns `false` only when the earlier group exists but couldn't be turned off; the pointer
    /// then still names it, so a later `unregister()` can retry.
    private func disablePreviousGroup(unless newIdentifier: String) -> Bool {
        guard let previous = defaults.string(forKey: Self.groupPointerKey), previous != newIdentifier else {
            return true
        }
        do {
            try InboxConfigStore(appGroupIdentifier: previous, group: group).disable()
        } catch InboxConfigError.groupUnavailable {
            InboxLog.warning("Previous App Group \(previous) is unavailable; nothing to turn off there.")
        } catch {
            InboxLog.error("registerForMobileInbox could not turn off the previous App Group (\(error)).")
            return false
        }
        return true
    }
}
