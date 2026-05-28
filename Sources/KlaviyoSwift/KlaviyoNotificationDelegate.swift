//
//  KlaviyoNotificationDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/13/26.
//

import Foundation
import UserNotifications

/// A proxy `UNUserNotificationCenterDelegate` that the SDK installs as the active
/// `UNUserNotificationCenter` delegate to intercept push notification responses automatically.
final class KlaviyoNotificationDelegate: NSObject {
    static let shared = KlaviyoNotificationDelegate()

    override private init() {}

    /// The host app's delegate that was in place before the SDK proxy was installed.
    ///
    /// `weak` mirrors `UNUserNotificationCenter.delegate`'s own weak contract — the SDK must
    /// not silently extend the lifetime of the host's delegate object.
    private weak var existingDelegate: (any UNUserNotificationCenterDelegate)?
}

// MARK: - UNUserNotificationCenterDelegate

extension KlaviyoNotificationDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // TODO: [MAGE-657] Forward to existingDelegate via OnceCallback
        // TODO: [MAGE-657] Call KlaviyoSDK().handle() for auto-tracking
        // TODO: [MAGE-660] Add double-track guard
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable
        (UNNotificationPresentationOptions) -> Void
    ) {
        // TODO: [MAGE-657] Forward to existingDelegate when present
        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner, .badge, .sound])
        } else {
            completionHandler([.alert, .badge, .sound])
        }
    }
}
