//
//  KlaviyoNotificationDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/13/26.
//

import Foundation
import UserNotifications

/// A proxy `UNUserNotificationCenterDelegate` that the SDK will install as the active
/// `UNUserNotificationCenter` delegate to intercept push notification responses automatically.
///
/// This initial implementation provides only the class shape and barebones delegate stubs.
/// Follow-on tickets will add:
/// - Injection at `initialize()` and KVO re-injection (MAGE-657)
/// - Forwarding callbacks to `existingDelegate` with once-style completion handler (MAGE-657)
/// - Auto-open tracking via `KlaviyoSDK().handle(notificationResponse:)` (MAGE-657)
/// - Double-track guard to prevent duplicate open events (MAGE-660)
final class KlaviyoNotificationDelegate: NSObject, @unchecked Sendable {
    static let shared = KlaviyoNotificationDelegate()
    
    /// The host app's delegate that was in place before the SDK proxy was installed.
    ///
    /// `weak` mirrors `UNUserNotificationCenter.delegate`'s own weak contract — the SDK must
    /// not silently extend the lifetime of the host's delegate object.
    weak var existingDelegate: (any UNUserNotificationCenterDelegate)?
}

// MARK: - UNUserNotificationCenterDelegate

extension KlaviyoNotificationDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // Forwarding to existingDelegate and auto-tracking added in MAGE-657/MAGE-660.
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable
        (UNNotificationPresentationOptions) -> Void
    ) {
        // Forwarding to existingDelegate added in MAGE-657.
        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
