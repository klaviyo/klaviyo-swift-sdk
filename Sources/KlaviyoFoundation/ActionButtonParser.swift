//
//  ActionButtonParser.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Where a push action button or notification leads, already validated against its action type.
/// `Codable` because the Mobile Inbox persists it; the encoded shape is part of that stored format.
package enum ActionButtonDestination: Equatable, Codable {
    case openApp
    case deepLink(URL)
    case openUrl(URL)

    /// `nil` when `url` does not fit `action`:
    /// - `open_app` must have no `url`
    /// - `deep_link` must have a parseable `url`, of any scheme
    /// - `open_url` must have a parseable `url` whose scheme is in ``openUrlAllowedSchemes``
    package init?(action: ActionType, url: String?) {
        switch action {
        case .openApp:
            guard url == nil else { return nil }
            self = .openApp
        case .deepLink:
            guard let url = url.flatMap({ URL(string: $0) }) else { return nil }
            self = .deepLink(url)
        case .openUrl:
            guard let url = url.flatMap({ URL(string: $0) }), url.hasAllowedOpenUrlScheme else { return nil }
            self = .openUrl(url)
        }
    }

    package var type: ActionType {
        switch self {
        case .openApp: return .openApp
        case .deepLink: return .deepLink
        case .openUrl: return .openUrl
        }
    }
}

/// A valid action button from a push payload.
package struct ActionButton: Equatable, Codable {
    package let id: String
    package let label: String
    package let destination: ActionButtonDestination

    package init(id: String, label: String, destination: ActionButtonDestination) {
        self.id = id
        self.label = label
        self.destination = destination
    }
}

/// Parses `body.action_buttons` from a push `userInfo`. Shared by the rich-push extension and the
/// Mobile Inbox so the two can never disagree about which buttons are valid.
///
/// ```json
/// {
///   "body": {
///     "action_buttons": [
///       { "id": "com.klaviyo.action.shop", "action": "deep_link", "label": "Shop Now", "url": "myapp://sale" }
///     ]
///   }
/// }
/// ```
///
/// Total: it never throws. A button is skipped, without affecting its neighbours, when it is not a
/// dictionary, lacks a non-empty `id` or `label`, has an unknown `action`, or has a `url` that does not
/// fit its action (see ``ActionButtonDestination/init(action:url:)``).
package enum ActionButtonParser {
    private enum Key {
        static let body = "body"
        static let actionButtons = "action_buttons"
        static let id = "id"
        static let label = "label"
        static let action = "action"
        static let url = "url"
    }

    /// - Parameter onSkip: Called with a short reason for each skipped button, for callers that log.
    package static func parse(
        userInfo: [AnyHashable: Any],
        onSkip: (String) -> Void = { _ in }
    ) -> [ActionButton] {
        guard let body = PayloadValue.dictionary(userInfo[Key.body]),
              let entries = body[Key.actionButtons] as? [Any] else {
            return []
        }
        var buttons: [ActionButton] = []
        for entry in entries {
            guard let data = PayloadValue.dictionary(entry) else {
                onSkip("Button is not a dictionary: \(entry)")
                continue
            }
            guard let id = data[Key.id] as? String, !id.isEmpty,
                  let label = data[Key.label] as? String, !label.isEmpty,
                  let actionString = data[Key.action] as? String,
                  let action = ActionType(rawValue: actionString) else {
                onSkip("Button is missing or has an empty id, label, and/or a known action: \(data)")
                continue
            }
            guard let destination = ActionButtonDestination(action: action, url: data[Key.url] as? String) else {
                onSkip("Button url is incompatible with its action: \(data)")
                continue
            }
            buttons.append(ActionButton(id: id, label: label, destination: destination))
        }
        return buttons
    }
}
