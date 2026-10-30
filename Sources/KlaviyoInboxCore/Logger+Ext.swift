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
    /// Logger for capturing delivered pushes in the Notification Service Extension.
    static let mobileInboxCapture = Logger(category: "Mobile Inbox Capture")

    /// Logger for the Inbox store: opening, migration, recovery, and write failures.
    static let mobileInboxStore = Logger(category: "Mobile Inbox Store")
}
