//
//  KlaviyoActionButtonParser.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

import Foundation
import KlaviyoCore
import OSLog
import UserNotifications

/// Represents a parsed action button definition from a push notification payload.
struct ActionButtonDefinition {
    let id: String
    let action: ActionType
    let label: String
    let url: String?
}

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
    /// - Returns: Array of parsed button definitions, or nil if none found
    static func parseActionButtons(from userInfo: [AnyHashable: Any]) -> [ActionButtonDefinition]? {
        // Extract body dictionary
        guard let body = userInfo["body"] as? [String: Any],
              let actionButtonsArray = body["action_buttons"] as? [[String: Any]],
              !actionButtonsArray.isEmpty else {
            if #available(iOS 14.0, *) {
                Logger.actionButtons.info("No action buttons found in notification payload")
            }
            return nil
        }

        // Parse each button definition
        var definitions: [ActionButtonDefinition] = []

        for buttonData in actionButtonsArray {
            guard let id = buttonData["id"] as? String,
                  let label = buttonData["label"] as? String,
                  let actionString = buttonData["action"] as? String,
                  let action = ActionType(rawValue: actionString) else {
                if #available(iOS 14.0, *) {
                    Logger.actionButtons.warning("Button data is missing or malformed. Missing an id, label, and/or action. Skipping button: \(buttonData.description)")
                }
                continue // Skip invalid button definitions
            }

            let url = buttonData["url"] as? String

            // Validate action-url combinations
            guard isValidActionURLCombination(action: action, url: url) else {
                if #available(iOS 14.0, *) {
                    Logger.actionButtons.warning("Button url is incompatible with its action. Skipping button: \(buttonData.description)")
                }
                continue
            }

            definitions.append(ActionButtonDefinition(
                id: id,
                action: action,
                label: label,
                url: url
            ))
        }

        return definitions.isEmpty ? nil : definitions
    }

    /// Creates an array of UNNotificationAction instances from button definitions.
    ///
    /// - Parameter definitions: Array of parsed button definitions
    /// - Returns: Array of UNNotificationAction instances
    static func createActions(from definitions: [ActionButtonDefinition]) -> [UNNotificationAction] {
        var actions: [UNNotificationAction] = []

        for definition in definitions {
            let action = createAction(from: definition)
            actions.append(action)
        }

        return actions
    }

    // MARK: - Private Methods

    /// Validates that an action type has the correct URL configuration.
    ///
    /// - `.openApp` actions should not have a URL
    /// - `.deepLink` actions must have a URL
    ///
    /// - Parameters:
    ///   - action: The action type to validate
    ///   - url: The optional URL string
    /// - Returns: `true` if the combination is valid, `false` otherwise
    private static func isValidActionURLCombination(action: ActionType, url: String?) -> Bool {
        switch action {
        case .openApp:
            return url == nil
        case .deepLink:
            return url != nil
        }
    }

    /// Creates a single UNNotificationAction from a button definition.
    ///
    /// - Parameter definition: The button definition to convert
    /// - Returns: A configured UNNotificationAction
    private static func createAction(from definition: ActionButtonDefinition) -> UNNotificationAction {
        UNNotificationAction(
            identifier: definition.id,
            title: definition.label,
            options: .foreground // Opens app when tapped
        )
    }
}
