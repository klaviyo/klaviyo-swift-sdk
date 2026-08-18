//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 5/27/25.
//

import KlaviyoCore
import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoSwift"

    init(category: String = #file) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Loggers

@available(iOS 14.0, *)
extension Logger {
    /// Logger for ``Codable`` events (JSON encoding & decoding)
    static var codableLogger: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "Encoding/Decoding Logger") : Logger(OSLog.disabled)
    }

    /// Logger for state events that run through the reducer
    static var stateLogger: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "State logger") : Logger(OSLog.disabled)
    }

    /// Logger for notification events.
    static var notifications: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "Notifications logger") : Logger(OSLog.disabled)
    }

    /// Logger for app navigation and deep linking events
    static var navigation: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(category: "Linking and Navigation") : Logger(OSLog.disabled)
    }
}
