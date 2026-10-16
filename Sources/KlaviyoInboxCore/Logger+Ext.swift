//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoInboxCore"

    init(category: String = #file) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Loggers

@available(iOS 14.0, *)
extension Logger {
    /// Logger for the Mobile Inbox configuration shared between the app and the Notification Service Extension.
    static let mobileInboxConfig = Logger(category: "Mobile Inbox Config")
    /// Logger for capturing delivered pushes in the Notification Service Extension.
    static let mobileInboxCapture = Logger(category: "Mobile Inbox Capture")
}
