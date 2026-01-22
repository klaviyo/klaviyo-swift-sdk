//
//  KlaviyoActionButtonParser.swift
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
            return nil
        }

        // Parse each button definition
        var definitions: [ActionButtonDefinition] = []

        for buttonData in actionButtonsArray {
            guard let id = buttonData["id"] as? String,
                  let label = buttonData["label"] as? String,
                  let actionString = buttonData["action"] as? String,
                  let action = ActionType(rawValue: actionString) else {
                continue // Skip invalid button definitions
            }

            let url = buttonData["url"] as? String

            if action == .openApp && url != nil {
                continue // openApp actions should not have an attached url
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
    /// Button reversal logic (iOS convention):
    /// - 2 buttons: Reversed (confirmatory action on right)
    /// - 1 or 3+ buttons: Original order
    ///
    /// - Parameter definitions: Array of parsed button definitions
    /// - Returns: Array of UNNotificationAction instances
    static func createActions(from definitions: [ActionButtonDefinition]) -> [UNNotificationAction] {
        var actions: [UNNotificationAction] = []

        for definition in definitions {
            let action = createAction(from: definition)
            actions.append(action)
        }

        // Apply iOS button reversal convention for 2-button layouts
        if actions.count == 2 {
            return actions.reversed()
        }

        return actions
    }

    // MARK: - Private Methods

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
