//
//  Logger+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/8/24.
//

import OSLog

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? ""

    /// Logs events related to location services.
    internal static let geoservices = Logger(subsystem: subsystem, category: "geoservices")
}
