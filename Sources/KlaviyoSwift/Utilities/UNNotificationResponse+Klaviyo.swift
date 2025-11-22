//
//  UNNotificationResponse+Klaviyo.swift
//
//  Klaviyo Swift SDK
//
//  Created for Klaviyo
//
//  Copyright (c) 2025 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog
import UserNotifications

extension UNNotificationResponse {
    /// Determines if a notification originated from Klaviyo.
    ///
    /// A notification is considered a Klaviyo notification if it contains
    /// a "body" dictionary with a "_k" key in its userInfo.
    public var isKlaviyoNotification: Bool {
        if let properties = notification.request.content.userInfo as? [String: Any],
           let body = properties["body"] as? [String: Any],
           let _ = body["_k"] {
            return true
        } else {
            return false
        }
    }

    /// Returns the custom Klaviyo properties from a Klaviyo notification payload, if present.
    var klaviyoProperties: [String: Any]? {
        guard isKlaviyoNotification else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Attempting to access Klaviyo properties from a non-Klaviyo notification.")
            }
            return nil
        }

        guard let properties = notification.request.content.userInfo as? [String: Any] else {
            if #available(iOS 14.0, *) {
                Logger.notifications.log("Unable to retrieve properties from the Klaviyo notification payload.")
            }
            return nil
        }

        return properties
    }

    /// Returns the deep link URL from a Klaviyo notification payload, if present.
    var klaviyoDeepLinkURL: URL? {
        guard isKlaviyoNotification else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Attempting to access a Klaviyo deep link URL from a non-Klaviyo notification.")
            }
            return nil
        }

        guard let properties = klaviyoProperties else {
            return nil
        }

        guard let urlString = properties["url"] as? String else {
            if #available(iOS 14.0, *) {
                Logger.notifications.log("Unable to retrieve deep link URL from the Klaviyo notification payload.")
            }
            return nil
        }

        guard let url = URL(string: urlString) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Unable to convert string '\(urlString)' to a valid URL.")
            }
            return nil
        }

        return url
    }

    // MARK: - Action Button Support

    /// Determines if the notification response is from an action button tap.
    ///
    /// Returns `true` if the user tapped an action button, `false` if they tapped
    /// the notification body or dismissed the notification.
    var isActionButtonTap: Bool {
        actionIdentifier != UNNotificationDefaultActionIdentifier &&
            actionIdentifier != UNNotificationDismissActionIdentifier
    }

    /// Returns the Klaviyo action identifier if this is a Klaviyo action button.
    ///
    /// For Klaviyo action buttons, this will be a value like "com.klaviyo.action.view"
    var klaviyoActionIdentifier: String? {
        guard isActionButtonTap else {
            return nil
        }

        // Check if it's a Klaviyo action (starts with our namespace)
        guard actionIdentifier.hasPrefix("com.klaviyo.action.") else {
            return nil
        }

        return actionIdentifier
    }

    /// Returns the deep link URL for the specific action button that was tapped.
    ///
    /// This extracts the URL from the action-specific metadata in the payload:
    /// ```json
    /// {
    ///   "body": {
    ///     "actions": {
    ///       "com.klaviyo.action.view": {
    ///         "url": "myapp://orders/12345"
    ///       }
    ///     }
    ///   }
    /// }
    /// ```
    var actionButtonURL: URL? {
        guard isActionButtonTap,
              isKlaviyoNotification,
              let properties = klaviyoProperties else {
            return nil
        }

        // Extract the body dictionary
        guard let body = properties["body"] as? [String: Any] else {
            return nil
        }

        // Extract the actions dictionary
        guard let actions = body["actions"] as? [String: Any] else {
            return nil
        }

        // Get the action metadata for this specific action identifier
        guard let actionData = actions[actionIdentifier] as? [String: Any] else {
            return nil
        }

        // Extract the URL string
        guard let urlString = actionData["url"] as? String else {
            return nil
        }

        // Convert to URL
        guard let url = URL(string: urlString) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning(
                    "Unable to convert action button URL string '\(urlString)' to a valid URL."
                )
            }
            return nil
        }

        return url
    }

    /// Returns metadata for the action button that was tapped, if available.
    ///
    /// This includes all custom properties associated with the action button
    /// from the notification payload.
    var actionButtonMetadata: [String: Any]? {
        guard isActionButtonTap,
              isKlaviyoNotification,
              let properties = klaviyoProperties else {
            return nil
        }

        guard let body = properties["body"] as? [String: Any],
              let actions = body["actions"] as? [String: Any],
              let actionData = actions[actionIdentifier] as? [String: Any] else {
            return nil
        }

        return actionData
    }
}
