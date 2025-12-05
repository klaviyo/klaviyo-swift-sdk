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
    /// Uses NSInvocation reflection to call iOS 15+ icon APIs dynamically,
    /// similar to OneSignal's approach. This allows the SDK to run on older
    /// iOS versions while supporting icons when available.
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
        // Attempt to create icon using UNNotificationActionIcon.iconWithSystemImageName:
        guard let iconClass = NSClassFromString("UNNotificationActionIcon") else {
            return createFallbackAction(id: id, label: label)
        }

        // Get the iconWithSystemImageName: selector
        let iconSelector = NSSelectorFromString("iconWithSystemImageName:")
        guard iconClass.responds(to: iconSelector) else {
            return createFallbackAction(id: id, label: label)
        }

        // Create the icon instance using performSelector
        guard let iconObject = iconClass.perform(iconSelector, with: icon)?.takeUnretainedValue() else {
            return createFallbackAction(id: id, label: label)
        }

        // Get the actionWithIdentifier:title:options:icon: selector
        let actionClass: AnyClass = UNNotificationAction.self
        let actionSelector = NSSelectorFromString("actionWithIdentifier:title:options:icon:")
        guard actionClass.responds(to: actionSelector) else {
            return createFallbackAction(id: id, label: label)
        }

        // Create NSMethodSignature
        guard let method = class_getClassMethod(actionClass, actionSelector),
              let signature = method_getTypeEncoding(method) else {
            return createFallbackAction(id: id, label: label)
        }

        // Create NSInvocation (using reflection to avoid direct API usage)
        let invocationClass = NSClassFromString("NSInvocation")
        let invocationSelector = NSSelectorFromString("invocationWithMethodSignature:")

        guard let invocationClass = invocationClass,
              let signatureObject = NSMethodSignature(cString: signature) else {
            return createFallbackAction(id: id, label: label)
        }

        guard let invocation = invocationClass.perform(invocationSelector, with: signatureObject)?.takeUnretainedValue() as? NSObject else {
            return createFallbackAction(id: id, label: label)
        }

        // Set up the invocation
        invocation.setValue(actionSelector, forKey: "selector")
        invocation.setValue(actionClass, forKey: "target")

        // Set arguments (indexes 0 and 1 are self and _cmd)
        var idArg: NSString = id as NSString
        var labelArg: NSString = label as NSString
        var optionsArg: UNNotificationActionOptions = .foreground
        var iconArg = iconObject

        withUnsafePointer(to: &idArg) { invocation.setArgument($0, at: 2) }
        withUnsafePointer(to: &labelArg) { invocation.setArgument($0, at: 3) }
        withUnsafePointer(to: &optionsArg) { invocation.setArgument($0, at: 4) }
        withUnsafePointer(to: &iconArg) { invocation.setArgument($0, at: 5) }

        // Invoke
        invocation.perform(NSSelectorFromString("invoke"))

        // Get return value
        var returnValue: Unmanaged<AnyObject>?
        withUnsafeMutablePointer(to: &returnValue) { pointer in
            invocation.perform(NSSelectorFromString("getReturnValue:"), with: pointer)
        }

        if let action = returnValue?.takeUnretainedValue() as? UNNotificationAction {
            return action
        }

        // Fallback if reflection fails
        return createFallbackAction(id: id, label: label)
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
