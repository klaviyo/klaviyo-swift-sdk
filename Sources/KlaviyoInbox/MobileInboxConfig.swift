//
//  MobileInboxConfig.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoInboxCore

/// Configuration for Mobile Inbox. Pass it to `registerForMobileInbox(configuration:)`.
public struct MobileInboxConfig: Equatable, Sendable {
    /// The number of messages kept on the device when `localRetentionLimit` isn't specified.
    public static let defaultLocalRetentionLimit = InboxLimits.defaultRetention

    /// How many messages are kept on the device, between 1 and 500 (default 100). Values outside that
    /// range are clamped and a warning is logged. When the limit is exceeded, the oldest messages are
    /// removed.
    public let localRetentionLimit: Int

    /// Mobile Inbox keeps its configuration in the App Group named by the `klaviyo_app_group` entry
    /// in your Info.plist: the same one you set up for badge counts.
    public init(localRetentionLimit: Int = MobileInboxConfig.defaultLocalRetentionLimit) {
        MobileInboxLogging.install()
        let clamped = InboxLimits.clampedRetention(localRetentionLimit)
        if clamped != localRetentionLimit {
            InboxLog.warning(
                "localRetentionLimit \(localRetentionLimit) is outside 1...500; using \(clamped)."
            )
        }
        self.localRetentionLimit = clamped
    }
}
