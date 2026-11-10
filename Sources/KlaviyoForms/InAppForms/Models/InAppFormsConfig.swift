//
//  InAppFormsConfig.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//
import Foundation
import OSLog

/// Options for in-app forms, passed to `registerForInAppForms(configuration:)`.
///
/// ```swift
/// // End the form session if the app stays in the background for 30 minutes.
/// let config = InAppFormsConfig(sessionTimeoutDuration: 30 * 60)
/// KlaviyoSDK().registerForInAppForms(configuration: config)
/// ```
public struct InAppFormsConfig {
    /// The duration in seconds after which a form session is considered expired.
    let sessionTimeoutDuration: TimeInterval

    /// Creates an in-app forms configuration.
    ///
    /// A form session ends when the app stays in the background for longer than
    /// `sessionTimeoutDuration`. When the app returns to the foreground after that, the SDK reloads
    /// forms and starts a new session.
    ///
    /// - Parameter sessionTimeoutDuration: How long, in seconds, the app can stay in the background
    ///   before the form session ends. Defaults to `3600` (one hour). Pass `0` to end the session
    ///   every time the app goes to the background, or `TimeInterval.infinity` to never end it. A
    ///   negative value is treated as `0`.
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
