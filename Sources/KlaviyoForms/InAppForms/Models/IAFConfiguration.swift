//
//  IAFConfiguration.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//
import Foundation

/// Configuration options for in-app forms
public struct IAFConfiguration {
    /// The duration in seconds for which a form session should be extended.
    public let sessionTimeoutDuration: TimeInterval

    /// Creates a new configuration for in-app forms
    /// - Parameter sessionTimeoutDuration: The duration in seconds for which a form session should be extended
    public init(sessionTimeoutDuration: TimeInterval) {
        self.sessionTimeoutDuration = sessionTimeoutDuration
    }
}
