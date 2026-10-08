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

    /// The App Group shared by your app and its Notification Service Extension, the same one
    /// you use for badge counts. Mobile Inbox keeps its configuration there.
    public let appGroupIdentifier: String

    /// How many messages are kept on the device, between 1 and 500 (default 100). Values outside that
    /// range are clamped and a warning is logged. When the limit is exceeded, the oldest messages are
    /// removed.
    public let localRetentionLimit: Int

    public init(
        appGroupIdentifier: String,
        localRetentionLimit: Int = MobileInboxConfig.defaultLocalRetentionLimit
    ) {
        MobileInboxLogging.install()
        self.appGroupIdentifier = appGroupIdentifier
        let clamped = InboxLimits.clampedRetention(localRetentionLimit)
        if clamped != localRetentionLimit {
            InboxLog.warning(
                "localRetentionLimit \(localRetentionLimit) is outside 1...500; using \(clamped)."
            )
        }
        self.localRetentionLimit = clamped
    }
}
