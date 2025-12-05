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
import UserNotifications

/// Represents a parsed action button definition from a push notification payload.
struct ActionButtonDefinition {
    let id: String
    let label: String
    let url: String?
    let icon: String?  // SF Symbol name for iOS 15+
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
///         "label": "Shop Now",
///         "url": "myapp://sale",
///         "icon": "cart.fill"
///       }
///     ]
///   }
/// }
/// ```
class KlaviyoActionButtonParser {

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
                  let label = buttonData["label"] as? String else {
                continue  // Skip invalid button definitions
            }

            let url = buttonData["url"] as? String
            let icon = buttonData["icon"] as? String

            definitions.append(ActionButtonDefinition(
                id: id,
                label: label,
                url: url,
                icon: icon
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
        // Try to create action with icon support (iOS 15+)
        if #available(iOS 15.0, *), let icon = definition.icon {
            return createActionWithIcon(
                id: definition.id,
                label: definition.label,
                icon: icon
            )
        }

        // Fallback to standard action without icon
        return UNNotificationAction(
            identifier: definition.id,
            title: definition.label,
            options: .foreground  // Opens app when tapped
        )
    }

    /// Creates a UNNotificationAction with an icon (iOS 15+).
    ///
    /// Uses runtime type checking to support iOS 15+ icon APIs while maintaining
    /// backwards compatibility with older iOS versions.
    ///
    /// - Parameters:
    ///   - id: The action identifier
    ///   - label: The button label text
    ///   - icon: SF Symbol name (e.g., "cart.fill")
    /// - Returns: A UNNotificationAction with icon if successful, plain action otherwise
    @available(iOS 15.0, *)
    private static func createActionWithIcon(
        id: String,
        label: String,
        icon: String
    ) -> UNNotificationAction {
        // Use runtime type checking for iOS 15+ APIs
        // UNNotificationActionIcon.iconWithSystemImageName: is available in iOS 15+
        let iconSelector = NSSelectorFromString("iconWithSystemImageName:")

        guard let iconClass = NSClassFromString("UNNotificationActionIcon"),
              let iconMethod = class_getClassMethod(iconClass, iconSelector) else {
            return createFallbackAction(id: id, label: label)
        }

        // Call the class method using typedPerform
        typealias IconCreator = @convention(c) (AnyClass, Selector, NSString) -> AnyObject
        let implementation = method_getImplementation(iconMethod)
        let function = unsafeBitCast(implementation, to: IconCreator.self)
        let iconObject = function(iconClass, iconSelector, icon as NSString)

        // Now create the action with icon
        // UNNotificationAction.actionWithIdentifier:title:options:icon: is available in iOS 15+
        let actionSelector = NSSelectorFromString("actionWithIdentifier:title:options:icon:")

        guard let actionMethod = class_getClassMethod(UNNotificationAction.self, actionSelector) else {
            return createFallbackAction(id: id, label: label)
        }

        // Call the action creation method
        typealias ActionCreator = @convention(c) (AnyClass, Selector, NSString, NSString, UInt, AnyObject) -> UNNotificationAction
        let actionImplementation = method_getImplementation(actionMethod)
        let actionFunction = unsafeBitCast(actionImplementation, to: ActionCreator.self)

        let action = actionFunction(
            UNNotificationAction.self,
            actionSelector,
            id as NSString,
            label as NSString,
            UNNotificationActionOptions.foreground.rawValue,
            iconObject
        )

        return action
    }

    /// Creates a standard action without icon (fallback).
    ///
    /// - Parameters:
    ///   - id: The action identifier
    ///   - label: The button label text
    /// - Returns: A UNNotificationAction without icon
    private static func createFallbackAction(id: String, label: String) -> UNNotificationAction {
        return UNNotificationAction(
            identifier: id,
            title: label,
            options: .foreground
        )
    }
}
