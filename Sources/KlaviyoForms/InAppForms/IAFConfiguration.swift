//
//  IAFConfiguration.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//
import Foundation

/// Configuration options for in-app forms
public struct IAFConfiguration {
    /// The duration in seconds for which a form session should be extended. Defaults to 3600 seconds (60 minutes).
    public let sessionTimeoutDuration: TimeInterval

    /// Creates a new configuration for in-app forms
    /// - Parameter sessionTimeoutDuration: The duration in seconds for which a form session should be extended. Defaults to 3600 seconds (60 minutes).
    public init(sessionTimeoutDuration: TimeInterval = 3600) {
        self.sessionTimeoutDuration = sessionTimeoutDuration
    }
}
