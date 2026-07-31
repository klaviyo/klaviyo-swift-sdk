//
//  KlaviyoActionButtonParser.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

import Foundation
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
    /// A button is renderable when it has an `id`, a `label`, and a recognized `action` —
    /// nothing more. A problem with its `url` degrades the button's *action*, not the button
    /// itself: the tap falls through to the `.foreground` option and opens the app. Dropping
    /// the button instead would silently discard what the sender configured, and would take
    /// every other button on the notification with it whenever no button survives.
    ///
    /// The `open_url` scheme allowlist is therefore enforced at dispatch time, in
    /// `KlaviyoSDK.handleActionButtonTap`, and not here.
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

            // Surface url/action mismatches without dropping the button — the tap will
            // fall through to opening the app rather than resolving the intended action.
            // `issue` embeds the sender-configured url, so it is marked private to match the
            // equivalent `web_url` rejection warning in `UNNotificationResponse.klaviyoWebUrl`.
            if let issue = urlIssue(for: action, url: url), #available(iOS 14.0, *) {
                Logger.actionButtons.warning(
                    "Button '\(id, privacy: .public)' will only open the app: \(issue, privacy: .private)"
                )
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

    /// Describes why `url` cannot satisfy `action`, or `nil` when the pairing is usable.
    ///
    /// Purely diagnostic — this never decides whether a button renders. See the discussion in
    /// ``parseActionButtons(from:)``.
    ///
    /// - Parameters:
    ///   - action: The button's action type
    ///   - url: The optional URL string
    /// - Returns: A message explaining the mismatch, or `nil` if there is none
    private static func urlIssue(for action: ActionType, url: String?) -> String? {
        switch action {
        case .openApp:
            return url == nil ? nil : "open_app buttons ignore the 'url' field"
        case .deepLink:
            guard let urlString = url else { return "deep_link buttons require a 'url'" }
            return URL(string: urlString) == nil ? "'\(urlString)' is not a parseable URL" : nil
        case .openUrl:
            guard let urlString = url else { return "open_url buttons require a 'url'" }
            guard let parsedUrl = URL(string: urlString) else {
                return "'\(urlString)' is not a parseable URL"
            }
            guard let scheme = parsedUrl.scheme?.lowercased() else {
                return "'\(urlString)' has no scheme; open_url needs a complete URL"
            }
            guard openUrlAllowedSchemes.contains(scheme) else {
                return "scheme '\(scheme)' is not in the allowed list \(openUrlAllowedSchemes.sorted())"
            }
            return nil
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
