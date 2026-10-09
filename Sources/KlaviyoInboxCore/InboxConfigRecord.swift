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
    case neverRegistered
    case enabled(localRetentionLimit: Int)
    case disabled
}

package enum InboxConfigError: Error, Equatable {
    case appGroupUnavailable
    case writeFailed
}
