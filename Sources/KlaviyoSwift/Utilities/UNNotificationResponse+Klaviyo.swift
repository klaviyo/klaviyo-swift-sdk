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
    ///
    /// This method checks the dynamic button format: `body.action_buttons[].url`
    ///
    /// Returns nil if no action-specific URL is found.
    var actionButtonURL: URL? {
        guard isActionButtonTap,
              isKlaviyoNotification,
              let properties = klaviyoProperties else {
            return nil
        }

        // Check dynamic format: body.action_buttons[].url
        if let body = properties["body"] as? [String: Any],
           let actionButtons = body["action_buttons"] as? [[String: Any]] {
            for button in actionButtons {
                if let id = button["id"] as? String,
                   id == actionIdentifier,
                   let urlString = button["url"] as? String,
                   let url = URL(string: urlString) {
                    return url
                }
            }
        }

        return nil
    }

    /// Returns the button label text (for analytics).
    ///
    /// This is available for dynamic action buttons that include a label in the payload.
    ///
    /// Returns nil if no label is found.
    var actionButtonLabel: String? {
        guard isActionButtonTap,
              isKlaviyoNotification,
              let properties = klaviyoProperties else {
            return nil
        }

        // Dynamic format: body.action_buttons[].label
        if let body = properties["body"] as? [String: Any],
           let actionButtons = body["action_buttons"] as? [[String: Any]] {
            for button in actionButtons {
                if let id = button["id"] as? String,
                   id == actionIdentifier,
                   let label = button["label"] as? String {
                    return label
                }
            }
        }

        return nil
    }

    /// Returns the action type for the tapped button.
    ///
    /// This method checks the dynamic button format: `body.action_buttons[].action`
    ///
    /// Returns nil if no action type is found or if the action is invalid.
    var actionButtonType: ActionType? {
        guard isActionButtonTap,
              isKlaviyoNotification,
              let properties = klaviyoProperties else {
            return nil
        }

        // Check dynamic format: body.action_buttons[].action
        if let body = properties["body"] as? [String: Any],
           let actionButtons = body["action_buttons"] as? [[String: Any]] {
            for button in actionButtons {
                if let id = button["id"] as? String,
                   id == actionIdentifier,
                   let actionString = button["action"] as? String {
                    return ActionType(rawValue: actionString)
                }
            }
        }

        return nil
    }
}
