//
//  InAppFormsConfig.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//
import Foundation
import OSLog

/// Configuration for In-App Forms functionality.
///
/// This struct provides configuration options for managing In-App Forms behavior,
/// including session management and timeout settings.
public struct InAppFormsConfig {
    /// The duration in seconds after which a form session is considered expired.
    let sessionTimeoutDuration: TimeInterval

    /// Short-lived credential that loads draft forms instead of published forms, or `nil`.
    let previewToken: String?

    /// Creates a new In-App Forms configuration.
    ///
    /// - Parameters:
    ///   - sessionTimeoutDuration: Duration (in seconds) of user inactivity after which the form session is terminated.
    ///     Defaults to 1 hour, must be non-negative.
    ///     Use 0 to timeout as soon as the app is backgrounded.
    ///     To disable session timeout altogether, use ``TimeInterval.infinity``.
    ///   - previewToken: Optional short-lived credential, generated from the Klaviyo form editor,
    ///     that loads draft forms for on-device testing instead of your published forms.
    ///     Never ship a preview token in a production build. `nil` or empty leaves any token set
    ///     with `setFormsPreviewToken(_:)` unchanged. The token is held in memory
    ///     only and never persisted.
    public init(sessionTimeoutDuration: TimeInterval = 3600, previewToken: String? = nil) {
        self.previewToken = previewToken
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

extension InAppFormsConfig: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacts ``previewToken`` so the credential never reaches logs.
    public var description: String {
        let token = previewToken?.isEmpty == false ? "<redacted>" : "nil"
        return "InAppFormsConfig(sessionTimeoutDuration: \(sessionTimeoutDuration), previewToken: \(token))"
    }

    public var debugDescription: String {
        description
    }
}
