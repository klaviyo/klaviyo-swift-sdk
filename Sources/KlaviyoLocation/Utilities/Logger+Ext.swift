//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/8/24.
//

import KlaviyoCore
import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoLocation"

    /// Logs events related to location services.
    static var geoservices: Logger {
        KlaviyoLogConfig.shared.isLoggingEnabled ? Logger(subsystem: subsystem, category: "geoservices") : Logger(OSLog.disabled)
    }
}
