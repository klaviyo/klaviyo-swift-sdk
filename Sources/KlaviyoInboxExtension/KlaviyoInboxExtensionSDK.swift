//
//  KlaviyoInboxExtensionSDK.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoInboxCore

/// Entry point for the Mobile Inbox Notification Service Extension integration.
///
/// Linking this module is what turns Mobile Inbox on: there is no register or unregister call.
public enum KlaviyoInboxExtensionSDK {}

extension KlaviyoInboxExtensionSDK {
    /// Captures a delivered Klaviyo push into Mobile Inbox. Call it from the Notification Service
    /// Extension's `didReceive` before any rich-media work, and await it (for example inside a
    /// `Task`) before calling the content handler so capture finishes first.
    ///
    /// Never throws. It waits at most one second for the store, then returns.
    ///
    /// - Important: Delivery needs `mutable-content: 1` on the push. Without it the system shows the
    ///   alert but never runs the extension, so nothing is captured.
    public static func capture(userInfo: [AnyHashable: Any]) async {
        _ = await InboxCapture().capture(userInfo: userInfo)
    }
}
