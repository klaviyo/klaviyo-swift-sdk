//
//  IAFConfiguration.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//
import Foundation

/// Configuration for in-app forms
public struct IAFConfiguration {
    public let sessionTimeoutDuration: TimeInterval

    /// - Parameter sessionTimeoutDuration: Duration (in seconds) of the period of user inactivity after which the user's app session is terminated and the forms session is ended. Defaults to 1 Hour.
    public init(sessionTimeoutDuration: TimeInterval = 3600) {
        self.sessionTimeoutDuration = sessionTimeoutDuration
    }
}
