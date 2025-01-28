//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 1/28/25.
//

import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = "com.klaviyo.klaviyo-swift-sdk.klaviyoUI"

    init(category: String = #file) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}

// MARK: - Loggers

@available(iOS 14.0, *)
extension Logger {
    /// Logger for Javascript console log messages from a WKWebView relayed to the native layer.
    static let webViewConsoleLogger = Logger(category: "WKWebView Console Log Relay")

    /// Logger for WKWebView related events.
    ///
    /// - Note: Javascript console logs relayed to the native layer should be handled by the ``webViewConsoleLogger``.
    static let webViewLogger = Logger(category: "WKWebView Event Handling")

    /// Logger for filesystem operations.
    static let filesystem = Logger(category: "Filesystem")
}
