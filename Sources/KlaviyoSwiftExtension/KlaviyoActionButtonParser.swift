//
//  KlaviyoActionButtonParser.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

import Foundation
import KlaviyoFoundation
import OSLog
import UserNotifications

/// Parses action button definitions from push notification payloads and creates UNNotificationAction instances.
///
/// This parser handles the dynamic action button format:
/// ```json
/// {
///   "body": {
///     "action_buttons": [
///       {
///         "id": "com.klaviyo.action.shop",
///         "action": "deep_link",
///         "label": "Shop Now",
///         "url": "myapp://sale"
///       }
///     ]
///   }
/// }
/// ```
enum KlaviyoActionButtonParser {
    // MARK: - Public Methods

    /// Parses action button definitions from a push notification payload.
    ///
    /// - Parameter userInfo: The notification's userInfo dictionary
    /// - Returns: Array of parsed buttons, or nil if none are valid
    static func parseActionButtons(from userInfo: [AnyHashable: Any]) -> [ActionButton]? {
        let buttons = ActionButtonParser.parse(userInfo: userInfo) { reason in
            if #available(iOS 14.0, *) {
                Logger.actionButtons.warning("Skipping action button. \(reason)")
            }
        }
        if buttons.isEmpty, #available(iOS 14.0, *) {
            Logger.actionButtons.info("No valid action buttons found in notification payload")
        }
        return buttons.isEmpty ? nil : buttons
    }

    /// Creates an array of UNNotificationAction instances from button definitions.
    ///
    /// - Parameter buttons: Array of parsed buttons
    /// - Returns: Array of UNNotificationAction instances
    static func createActions(from buttons: [ActionButton]) -> [UNNotificationAction] {
        buttons.map(createAction(from:))
    }

    // MARK: - Private Methods

    /// Creates a single UNNotificationAction from a button definition.
    ///
    /// - Parameter button: The button to convert
    /// - Returns: A configured UNNotificationAction
    private static func createAction(from button: ActionButton) -> UNNotificationAction {
        UNNotificationAction(
            identifier: button.id,
            title: button.label,
            options: .foreground // Opens app when tapped
        )
    }
}
