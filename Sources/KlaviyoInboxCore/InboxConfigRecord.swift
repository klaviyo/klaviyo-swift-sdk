//
//  InboxConfigRecord.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

/// The persisted, cross-process Mobile Inbox configuration. Read by the app and the Notification
/// Service Extension; written only by the app. Keep the JSON shape stable: an older extension may
/// read a file written by a newer app.
package struct InboxConfigRecord: Codable, Equatable {
    package static let currentVersion = 1

    package var version: Int
    package var enabled: Bool
    package var localRetentionLimit: Int

    package init(
        version: Int = InboxConfigRecord.currentVersion,
        enabled: Bool,
        localRetentionLimit: Int
    ) {
        self.version = version
        self.enabled = enabled
        self.localRetentionLimit = localRetentionLimit
    }
}

package enum InboxEnablement: Equatable {
    /// Reachable App Group with no config file: the app has not called `registerForMobileInbox`.
    case neverRegistered
    case enabled(localRetentionLimit: Int)
    /// The app opted out, or the file is corrupt or from an unsupported version.
    case disabled
    /// The state could not be determined: the `klaviyo_app_group` Info.plist entry is missing, the
    /// App Group is unreachable, or the file exists but cannot be read (for example while the device
    /// is locked). Distinct from `.disabled` so callers can tell a setup problem from an opt-out.
    case unavailable
}

package enum InboxConfigError: Error, Equatable {
    case appGroupUnavailable
    case writeFailed
}
