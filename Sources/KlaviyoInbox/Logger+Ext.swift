//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoCore
import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoInbox"

    init(category: String = #file) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Loggers

@available(iOS 14.0, *)
extension Logger {
    /// Logger for Mobile Inbox registration events.
    static var mobileInbox: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "Mobile Inbox") : Logger(OSLog.disabled)
    }
}
