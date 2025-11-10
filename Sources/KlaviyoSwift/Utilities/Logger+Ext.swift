//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 5/27/25.
//

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
    static let codableLogger = Logger(category: "Encoding/Decoding Logger")

    /// Logger for state events that run through the reducer
    static let stateLogger = Logger(category: "State logger")

    /// Logger for notification events.
    static let notifications = Logger(category: "Notifications logger")

    /// Logger for app navigation and deep linking events
    static let navigation = Logger(category: "Linking and Navigation")
}
