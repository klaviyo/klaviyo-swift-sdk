//
// Logger+Ext.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoCore"

    init(category: String) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Loggers

@available(iOS 14.0, *)
extension Logger {
    /// Logger for ``Codable`` events (JSON encoding & decoding)
    static let codable = Logger(category: "Encoding/Decoding Logger")

    /// Logger for networking events
    static let networking = Logger(category: "Networking")

    /// Logger for app navigation and deep linking events
    static let navigation = Logger(category: "Linking and Navigation")

    /// Logger for notification category management
    static let notifications = Logger(category: "Notifications")
}
