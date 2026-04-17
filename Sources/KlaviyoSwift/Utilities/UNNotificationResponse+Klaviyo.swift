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
import KlaviyoCore
import OSLog
import UserNotifications

extension UNNotificationResponse {
    /// Determines if a notification originated from Klaviyo.
    ///
    /// A notification is considered a Klaviyo notification if it contains
    /// a "body" dictionary with a "_k" key in its userInfo.
    public var isKlaviyoNotification: Bool {
        notification.request.content.userInfo.isKlaviyoNotification()
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

    /// Detects if the user tapped an action button (vs tapping the notification body).
    ///
    /// Returns `true` if the user tapped an action button, `false` if they tapped
    /// the notification body or dismissed it.
    var isActionButtonTap: Bool {
        actionIdentifier != UNNotificationDefaultActionIdentifier &&
            actionIdentifier != UNNotificationDismissActionIdentifier
    }

    /// Returns the action button ID that was tapped (if any).
    ///
    /// This returns the button's identifier string (e.g., "com.klaviyo.action.shop")
    /// if the user tapped an action button, or nil otherwise.
    var actionButtonId: String? {
        guard isActionButtonTap else { return nil }
        return actionIdentifier
    }

    /// Returns the action-specific deep link URL from the payload.
    var actionButtonURL: URL? {
        guard let urlString = matchingActionButton?["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    /// Returns the button label text (for analytics).
    var actionButtonLabel: String? {
        matchingActionButton?["label"] as? String
    }

    /// Returns the action type for the tapped button.
    var actionButtonType: ActionType? {
        guard let actionString = matchingActionButton?["action"] as? String else { return nil }
        return ActionType(rawValue: actionString)
    }

    // MARK: - Private Helpers

    /// Returns the action button dictionary matching the tapped action identifier, if any.
    private var matchingActionButton: [String: Any]? {
        guard isActionButtonTap,
              isKlaviyoNotification,
              let properties = klaviyoProperties,
              let body = properties["body"] as? [String: Any],
              let actionButtons = body["action_buttons"] as? [[String: Any]] else {
            return nil
        }
        return actionButtons.first { $0["id"] as? String == actionIdentifier }
    }
}
