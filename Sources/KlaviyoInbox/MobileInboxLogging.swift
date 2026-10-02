//
//  MobileInboxLogging.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoCore
import KlaviyoInboxCore

enum MobileInboxLogging {
    /// Points the Inbox logger at the SDK-wide logging switch. Idempotent; call before logging.
    static func install() {
        InboxLog.isEnabled = { KlaviyoLogConfig.shared.isLoggingEnabled }
    }
}
