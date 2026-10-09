//
//  KlaviyoInboxExtensionSDK.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoInboxCore

/// Entry point for the Mobile Inbox Notification Service Extension integration.
///
/// Capture is added by the NSE capture work; this type currently only carries the cross-process
/// enablement lookup that capture gates on.
public enum KlaviyoInboxExtensionSDK {}

extension KlaviyoInboxExtensionSDK {
    /// Whether Mobile Inbox is enabled, read from the App Group named by the extension's
    /// `klaviyo_app_group` Info.plist entry. Needs no running app and no initialized SDK.
    package static func enablement(group: InboxAppGroup = .system) -> InboxEnablement {
        InboxConfigStore(group: group).enablement()
    }

    /// Captures a delivered Klaviyo push into Mobile Inbox. Call it from the Notification Service
    /// Extension's `didReceive` before any rich-media work, then continue with normal handling.
    ///
    /// Never throws and never blocks the notification: when Mobile Inbox is not registered, the
    /// payload is not a Klaviyo push, or storing fails, it returns without effect. Await it (for
    /// example inside a `Task`) before calling the content handler so capture finishes first.
    ///
    /// - Important: Delivery needs `mutable-content: 1` on the push. Without it the system shows the
    ///   alert but never runs the extension, so nothing is captured.
    public static func capture(userInfo: [AnyHashable: Any]) async {
        _ = await capture(userInfo: userInfo, using: InboxCapture())
    }

    package static func capture(
        userInfo: [AnyHashable: Any],
        using capture: InboxCapture
    ) async -> InboxCaptureResult {
        await capture.capture(userInfo: userInfo)
    }
}
