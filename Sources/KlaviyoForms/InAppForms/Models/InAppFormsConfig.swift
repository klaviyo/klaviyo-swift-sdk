//
//  InAppFormsConfig.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//
import Foundation
import OSLog

/// Configuration for in-app forms
public struct InAppFormsConfig {
    /// - Parameter sessionTimeoutDuration: Duration (in seconds) of user inactivity after which the form session is terminated.
    ///   Defaults to 1 Hour, must be non-negative. Use 0 to timeout as soon as the app is backgrounded.
    ///   To disable session timeout altogether, use TimeInterval.infinity.
    public let sessionTimeoutDuration: TimeInterval

    public init(sessionTimeoutDuration: TimeInterval = 3600) {
        if sessionTimeoutDuration < 0 {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("`sessionTimeoutDuration` cannot be negative, 0s will be used instead.")
            }
            self.sessionTimeoutDuration = 0
        } else {
            self.sessionTimeoutDuration = sessionTimeoutDuration
        }
    }
}
