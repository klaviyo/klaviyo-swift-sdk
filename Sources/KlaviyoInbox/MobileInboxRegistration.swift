//
//  MobileInboxRegistration.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import KlaviyoInboxCore
import OSLog

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
        do {
            try store.enable(localRetentionLimit: configuration.localRetentionLimit)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.mobileInbox.error("registerForMobileInbox failed; Mobile Inbox stays off (\(error, privacy: .public)).")
            }
        }
    }

    func unregister() {
        // `.unavailable` falls through so `disable()` surfaces the real cause in the error log below.
        guard store.enablement() != .neverRegistered else {
            if #available(iOS 14.0, *) {
                Logger.mobileInbox.warning("unregisterFromMobileInbox called but Mobile Inbox was never registered.")
            }
            return
        }
        do {
            try store.disable()
        } catch {
            if #available(iOS 14.0, *) {
                Logger.mobileInbox.error("unregisterFromMobileInbox failed; Mobile Inbox may still be on (\(error, privacy: .public)).")
            }
        }
    }
}
