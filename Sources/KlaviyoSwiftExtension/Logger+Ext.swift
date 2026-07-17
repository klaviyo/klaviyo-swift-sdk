//
// Logger+Ext.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoSwiftExtension"

    init(category: String = #file) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Loggers

@available(iOS 14.0, *)
extension Logger {
    /// Logger for Push Action Buttons
    static let actionButtons = Logger(category: "Action Buttons")
    /// Logger for Rich Media
    static let richMedia = Logger(category: "Rich Media")
    /// Logger for notification category management
    static let notifications = Logger(category: "Notifications")
}
