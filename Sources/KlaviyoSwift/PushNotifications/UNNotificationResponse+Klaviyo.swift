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

extension UNNotification {
    /// Determines if this notification originated from Klaviyo.
    ///
    /// A notification is considered a Klaviyo notification if it contains
    /// a "body" dictionary with a "_k" key in its userInfo.
    public var isKlaviyoNotification: Bool {
        request.content.isKlaviyoNotification
    }
}

extension UNNotificationResponse {
    /// Determines if a notification originated from Klaviyo.
    ///
    /// A notification is considered a Klaviyo notification if it contains
    /// a "body" dictionary with a "_k" key in its userInfo.
    public var isKlaviyoNotification: Bool {
        notification.isKlaviyoNotification
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

    /// Returns the deep link URL from `properties`, a Klaviyo notification payload that may have
    /// had its forms preview token removed, if present.
    func klaviyoDeepLinkURL(in properties: [String: Any]) -> URL? {
        guard let urlString = properties["url"] as? String else {
            if #available(iOS 14.0, *) {
                Logger.notifications.log("Unable to retrieve deep link URL from the Klaviyo notification payload.")
            }
            return nil
        }

        guard let url = URL(string: urlString) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Unable to convert string '\(urlString, privacy: .private)' to a valid URL.")
            }
            return nil
        }

        return url
    }

    // MARK: - Forms Preview

    /// The in-app forms preview token carried by this push, and the notification properties with
    /// it removed. Reads a string `key_value_pairs["klaviyo-forms-preview"]`, falling back to the
    /// `klaviyo-forms-preview` query parameter of the tapped action button's `url`, then the `url`
    /// deep link, then the `web_url`. The key is removed from all of those, and from the `url` of
    /// every button in `body.action_buttons`, whether or not its value is a string or well formed.
    /// Links are edited as text, so every other byte is kept, and they are edited even when they
    /// are not valid URLs. Has no side effects. The token is not validated; see
    /// ``FormsPreviewTokenStore/validate(_:)``.
    func klaviyoFormsPreview(in properties: [String: Any]) -> (token: String?, properties: [String: Any]) {
        var stripped = properties
        var token: String?

        if var keyValuePairs = properties["key_value_pairs"] as? [String: Any],
           let value = keyValuePairs.removeValue(forKey: FormsPreview.previewTokenKey) {
            token = value as? String
            stripped["key_value_pairs"] = keyValuePairs
        }

        if var body = properties["body"] as? [String: Any],
           let buttons = body["action_buttons"] as? [[String: Any]] {
            var changed = false
            let strippedButtons = buttons.map { button -> [String: Any] in
                guard let urlString = button["url"] as? String,
                      let parameter = FormsPreview.previewTokenParameter(inURLString: urlString) else {
                    return button
                }
                if isActionButtonTap, button["id"] as? String == actionIdentifier {
                    token = token ?? parameter
                }
                changed = true
                var strippedButton = button
                strippedButton["url"] = FormsPreview.removingPreviewTokenParameter(fromURLString: urlString)
                return strippedButton
            }
            if changed {
                body["action_buttons"] = strippedButtons
                stripped["body"] = body
            }
        }

        for key in ["url", "web_url"] {
            if let urlString = properties[key] as? String,
               let parameter = FormsPreview.previewTokenParameter(inURLString: urlString) {
                token = token ?? parameter
                stripped[key] = FormsPreview.removingPreviewTokenParameter(fromURLString: urlString)
            }
        }

        return (token, stripped)
    }

    // MARK: - Dedup Key

    /// Returns the stable dedup key used by the auto-track guard to prevent double-firing
    /// the `Opened Push` event when both the Klaviyo proxy delegate and a manual
    /// `handle(notificationResponse:)` call process the same response.
    ///
    /// Preference order:
    /// 1. `tm` from `_k` — a ULID unique per delivery, always present in Klaviyo campaign sends.
    /// 2. `notification.request.identifier` — reached only for non-Klaviyo notifications (no `_k`
    ///    payload). In that path `handle(notificationResponse:)` returns `false` so
    ///    `markAsAutoTracked` is never called; the dedup guard never acts on this key.
    ///    `request.identifier` is intentionally not used as a unique-per-delivery key — it is a
    ///    display identity that can be shared across deliveries via `apns-collapse-id`.
    var klaviyoDedupKey: String {
        guard let userInfo = notification.request.content.userInfo as? [String: Any],
              let klaviyoBody = userInfo["body"] as? [String: Any],
              let kPayload = klaviyoBody["_k"] as? [String: Any],
              let deliveryUlid = kPayload["tm"] as? String else {
            return notification.request.identifier
        }
        return deliveryUlid
    }

    /// Returns the external web URL from this notification's payload, if present; see
    /// ``klaviyoWebUrl(in:)``.
    var klaviyoWebUrl: URL? {
        guard isKlaviyoNotification else {
            return nil
        }
        return klaviyoWebUrl(in: klaviyoProperties ?? [:])
    }

    /// Returns the external web URL from `properties`, a Klaviyo notification payload that may
    /// have had its forms preview token removed, if present.
    ///
    /// Reads the `web_url` field. The presence of this field indicates the tap should open
    /// the URL externally rather than route through the app's deep link handler.
    /// Returns `nil` if the field is absent, the value is not a parseable URL, or the URL's
    /// scheme is not in ``openUrlAllowedSchemes`` — unlisted schemes are dropped silently to
    /// prevent dangerous schemes (e.g. `javascript:`, `file:`) from being opened.
    func klaviyoWebUrl(in properties: [String: Any]) -> URL? {
        guard let urlString = properties["web_url"] as? String, !urlString.isEmpty else {
            return nil
        }

        guard let url = URL(string: urlString) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Unable to convert web_url string '\(urlString, privacy: .private)' to a valid URL.")
            }
            return nil
        }

        guard url.hasAllowedOpenUrlScheme else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning(
                    """
                    web_url '\(urlString, privacy: .private)' has a scheme not in the \
                    allowed list; ignoring.
                    """
                )
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

    /// Returns the tapped action button's URL from `properties`, a Klaviyo notification payload
    /// that may have had its forms preview token removed.
    func actionButtonURL(in properties: [String: Any]) -> URL? {
        guard let urlString = matchingActionButton(in: properties)?["url"] as? String else { return nil }
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
        klaviyoProperties.flatMap(matchingActionButton(in:))
    }

    /// Returns the action button dictionary in `properties` matching the tapped action identifier.
    private func matchingActionButton(in properties: [String: Any]) -> [String: Any]? {
        guard isActionButtonTap,
              isKlaviyoNotification,
              let body = properties["body"] as? [String: Any],
              let actionButtons = body["action_buttons"] as? [[String: Any]] else {
            return nil
        }
        return actionButtons.first { $0["id"] as? String == actionIdentifier }
    }
}
