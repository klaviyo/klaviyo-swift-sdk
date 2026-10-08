//
//  MobileInboxRegistration.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore

/// Turns Mobile Inbox capture on and off by writing the shared configuration file in the App Group
/// named by the `klaviyo_app_group` Info.plist entry.
final class MobileInboxRegistration {
    /// Replaced in tests. Production reads the real App Group.
    static var current = MobileInboxRegistration()

    private let store: InboxConfigStore

    init(group: InboxAppGroup = .system) {
        store = InboxConfigStore(group: group)
    }

    func register(_ configuration: MobileInboxConfig) {
        MobileInboxLogging.install()
        do {
            try store.enable(localRetentionLimit: configuration.localRetentionLimit)
        } catch {
            InboxLog.error("registerForMobileInbox failed; Mobile Inbox stays off (\(error)).")
        }
    }

    func unregister() {
        MobileInboxLogging.install()
        guard store.enablement() != .neverRegistered else {
            InboxLog.warning("unregisterFromMobileInbox called but Mobile Inbox was never registered.")
            return
        }
        do {
            try store.disable()
        } catch {
            InboxLog.error("unregisterFromMobileInbox failed; Mobile Inbox may still be on (\(error)).")
        }
    }
}
