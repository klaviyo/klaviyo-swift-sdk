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

    /// Positive, finite preload-to-handshake budget, after the initial JWT wait.
    /// `nil` uses the SDK's existing network timeout.
    public let loadTimeout: TimeInterval?

    /// Recent analytics history to replay after the handshake, bounded to 0...30 seconds.
    /// Also bounds how long the latest manual form request waits for forms data on an active runtime.
    /// Zero disables historical replay and manual waiting; live events and ready requests still dispatch.
    public let eventReplayWindow: TimeInterval

    /// Called on the main thread after teardown for a terminal initialization failure.
    /// Register again to retry. A missing eligible form does not invoke this callback.
    public let onFailure: (() -> Void)?

    /// Creates a new In-App Forms configuration.
    ///
    /// - Parameters:
    ///   - sessionTimeoutDuration: Duration (in seconds) of user inactivity after which the form session is
    /// terminated.
    ///     Defaults to 1 hour, must be non-negative.
    ///     Use 0 to timeout as soon as the app is backgrounded.
    ///     To disable session timeout altogether, use ``TimeInterval.infinity``.
    ///   - loadTimeout: Positive, finite loading budget in seconds, after the initial JWT wait.
    ///     Omitted or invalid values use the existing SDK network timeout.
    ///   - eventReplayWindow: Analytics replay and manual form waiting in seconds, clamped to 0...30.
    ///     Defaults to 10. Pending requests expire when their age reaches this window.
    ///   - onFailure: Main-thread callback after teardown for terminal pre-handshake initialization failure.
    public init(
        sessionTimeoutDuration: TimeInterval = 3600,
        loadTimeout: TimeInterval? = nil,
        eventReplayWindow: TimeInterval = 10,
        onFailure: (() -> Void)? = nil
    ) {
        if let loadTimeout {
            let nanoseconds = loadTimeout * 1_000_000_000
            if loadTimeout.isFinite, loadTimeout > 0,
               nanoseconds >= 1, nanoseconds < Double(UInt64.max) {
                self.loadTimeout = loadTimeout
            } else {
                self.loadTimeout = nil
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger
                        .warning("`loadTimeout` must be positive and finite; using the network timeout.")
                }
            }
        } else {
            self.loadTimeout = nil
        }
        self.eventReplayWindow = eventReplayWindow.isNaN ? 10 : min(30, max(0, eventReplayWindow))
        self.onFailure = onFailure
        if sessionTimeoutDuration < 0 {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger
                    .warning("`sessionTimeoutDuration` cannot be negative, 0s will be used instead.")
            }
            self.sessionTimeoutDuration = 0
        } else {
            self.sessionTimeoutDuration = sessionTimeoutDuration
        }
    }
}
