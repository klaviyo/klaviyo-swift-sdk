//
// NotificationService.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import KlaviyoSwiftExtension
import UIKit
import UserNotifications

// MARK: notification service extension implementation.

/// When push payload is marked as there being mutable-content this service
/// (more specifically the `didReceiveNotificationRequest` ) is called to perform
/// tasks such as downloading media (images or videos) and attaching it to the notification before it's displayed to the user.
///
/// Supported media formats:
/// - Images: PNG, JPG/JPEG, GIF
/// - Videos: MP4, MPEG
///
/// There is a limited time before which `didReceiveNotificationRequest`  needs to wrap up it's operations
/// else the notification is displayed as received.
///
/// Any property from `UNMutableNotificationContent` can be mutated here before presenting the notification.
class NotificationService: UNNotificationServiceExtension {
    var request: UNNotificationRequest!
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.request = request
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if let bestAttemptContent = bestAttemptContent {
            KlaviyoExtensionSDK.handleNotificationServiceDidReceivedRequest(
                request: self.request,
                bestAttemptContent: bestAttemptContent,
                contentHandler: contentHandler
            )
        }

        #if DEBUG
        // Access key-value pairs
        let customData = PushPayload.customData(from: request.content.userInfo)
        if customData.isEmpty {
            print("No key_value_pairs found in notification")
        } else {
            for (pairKey, value) in customData {
                print("Key: \(pairKey), Value: \(value)")
            }
        }
        #endif
    }

    override func serviceExtensionTimeWillExpire() {
        /// Called just before the extension will be terminated by the system.
        /// Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            KlaviyoExtensionSDK.handleNotificationServiceExtensionTimeWillExpireRequest(
                request: request,
                bestAttemptContent: bestAttemptContent,
                contentHandler: contentHandler
            )
        }
    }
}
