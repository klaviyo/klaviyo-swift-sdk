//
//  InboxLog.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import os

/// Extension-safe logger for the Inbox modules. `KlaviyoInbox` points `isEnabled` at the SDK-wide
/// logging switch; the extension side has no switch and always logs.
package enum InboxLog {
    package static var isEnabled: () -> Bool = { true }
    package static var recorder: ((OSLogType, String) -> Void)?

    private static let log = OSLog(
        subsystem: "com.klaviyo.klaviyo-swift-sdk.klaviyoInbox",
        category: "Mobile Inbox"
    )

    package static func warning(_ message: String) {
        emit(message, type: .default)
    }

    package static func error(_ message: String) {
        emit(message, type: .error)
    }

    private static func emit(_ message: String, type: OSLogType) {
        guard isEnabled() else { return }
        recorder?(type, message)
        os_log(type, log: log, "%{public}@", message as NSString)
    }
}
