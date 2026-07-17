//
// Logger+Ext.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? ""

    /// Logs events related to location services.
    static let geoservices = Logger(subsystem: subsystem, category: "geoservices")
}
