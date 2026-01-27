//
//  InAppFormsConfig.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//
import Foundation
import OSLog
import UIKit

/// The presentation style for In-App Forms.
public enum InAppFormsPresentationStyle {
    /// Presents the form as a modal overlay (default).
    case modal
    /// Presents the form in its own resizable window.
    case resizableWindow(initialSize: CGSize = CGSize(width: 200, height: 200), minimumSize: CGSize = CGSize(width: 200, height: 200))
}

/// Configuration for In-App Forms functionality.
///
/// This struct provides configuration options for managing In-App Forms behavior,
/// including session management and timeout settings.
public struct InAppFormsConfig {
    /// The duration in seconds after which a form session is considered expired.
    let sessionTimeoutDuration: TimeInterval

    /// The presentation style for In-App Forms.
    let presentationStyle: InAppFormsPresentationStyle

    /// Creates a new In-App Forms configuration.
    ///
    /// - Parameters:
    ///   - sessionTimeoutDuration: Duration (in seconds) of user inactivity after which the form session is terminated.
    ///     Defaults to 1 hour, must be non-negative.
    ///     Use 0 to timeout as soon as the app is backgrounded.
    ///     To disable session timeout altogether, use ``TimeInterval.infinity``.
    ///   - presentationStyle: The style used to present In-App Forms. Defaults to `.modal`.
    ///     Use `.resizableWindow()` to present forms in their own resizable window.
    public init(sessionTimeoutDuration: TimeInterval = 3600, presentationStyle: InAppFormsPresentationStyle = .modal) {
        if sessionTimeoutDuration < 0 {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("`sessionTimeoutDuration` cannot be negative, 0s will be used instead.")
            }
            self.sessionTimeoutDuration = 0
        } else {
            self.sessionTimeoutDuration = sessionTimeoutDuration
        }
        self.presentationStyle = presentationStyle
    }
}
