//
//  KlaviyoCarouselParser.swift
//

import Foundation
import OSLog

/// A carousel card parsed from a push notification payload.
struct CarouselCardDefinition: Equatable {
    /// The card's 1-based index in `carousel_cards`, assigned before invalid cards are dropped,
    /// so it matches the position the backend reports on. The payload carries no `position` key.
    let position: Int
    let imageURL: URL
    let title: String?
    let description: String?
    let action: ActionType
    let url: String?
}

/// Parses carousel cards from push notification payloads.
///
/// Cards live in `body.carousel_cards`:
/// ```json
/// {
///   "body": {
///     "carousel_cards": [
///       {
///         "image_url": "https://cdn.example.com/card-1.jpg",
///         "title": "Summer sale",
///         "description": "Up to 50% off",
///         "action": "deep_link",
///         "url": "myapp://sale"
///       }
///     ]
///   }
/// }
/// ```
///
/// The validation rules match the Android SDK so both platforms drop the same cards.
enum KlaviyoCarouselParser {
    static let minimumCards = 2
    static let maximumCards = 5

    /// The only schemes a card's `image_url` may use. Images are only fetched over the network.
    private static let imageSchemes: Set<String> = ["http", "https"]

    /// Whether the payload carries a `carousel_cards` array at all, valid or not.
    static func hasCarouselCards(_ userInfo: [AnyHashable: Any]) -> Bool {
        rawCards(in: userInfo) != nil
    }

    /// Parses carousel cards from a push notification payload.
    ///
    /// Invalid cards are skipped with a warning that names the card's position, never its URLs.
    ///
    /// - Parameter userInfo: The notification's userInfo dictionary
    /// - Returns: The valid cards in payload order, or nil unless ``minimumCards`` to
    ///   ``maximumCards`` valid cards remain, in which case the push should render as a standard notification
    static func parseCards(from userInfo: [AnyHashable: Any]) -> [CarouselCardDefinition]? {
        guard let rawCards = rawCards(in: userInfo) else { return nil }

        let cards = rawCards.enumerated().compactMap { index, rawCard in
            parseCard(rawCard, position: index + 1)
        }

        guard (minimumCards...maximumCards).contains(cards.count) else {
            if #available(iOS 14.0, *) {
                Logger.carousel.warning("\(cards.count) valid carousel card(s); \(minimumCards) to \(maximumCards) required. Falling back to a standard notification.")
            }
            return nil
        }
        return cards
    }

    // MARK: - Private Methods

    private static func rawCards(in userInfo: [AnyHashable: Any]) -> [Any]? {
        guard let body = userInfo["body"] as? [String: Any] else { return nil }
        return body["carousel_cards"] as? [Any]
    }

    private static func parseCard(_ rawCard: Any, position: Int) -> CarouselCardDefinition? {
        guard let card = rawCard as? [String: Any] else {
            warn(position, "not an object")
            return nil
        }

        guard let imageURLString = nonBlankString(card["image_url"]),
              let imageURL = URL(string: imageURLString),
              let imageScheme = imageURL.scheme?.lowercased() else {
            warn(position, "missing or invalid image_url")
            return nil
        }
        guard imageSchemes.contains(imageScheme) else {
            warn(position, "image_url scheme '\(imageScheme)' is not allowed")
            return nil
        }
        guard let host = imageURL.host, !host.isEmpty else {
            warn(position, "image_url has no host")
            return nil
        }

        guard let actionString = nonBlankString(card["action"]) else {
            warn(position, "missing required action")
            return nil
        }
        guard let action = ActionType(rawValue: actionString) else {
            warn(position, "unsupported action type")
            return nil
        }

        let url = nonBlankString(card["url"])
        // A non-string url (e.g. 42) still counts as present, as on Android, so open_app rejects it
        let urlPresent = isPresent(card["url"])
        guard isValidActionURLCombination(action: action, url: url, urlPresent: urlPresent, position: position) else {
            return nil
        }

        return CarouselCardDefinition(
            position: position,
            imageURL: imageURL,
            title: nonBlankString(card["title"]),
            description: nonBlankString(card["description"]),
            action: action,
            url: url
        )
    }

    /// Unlike action buttons, a card's `url` must be absent for `open_app`, and present and
    /// parseable for `deep_link` and `open_url`. An `open_url` scheme must be in ``openUrlAllowedSchemes``.
    private static func isValidActionURLCombination(
        action: ActionType,
        url: String?,
        urlPresent: Bool,
        position: Int
    ) -> Bool {
        switch action {
        case .openApp:
            guard !urlPresent else {
                warn(position, "open_app must not carry a url")
                return false
            }
            return true
        case .deepLink:
            guard let url, URL(string: url) != nil else {
                warn(position, "deep_link missing or invalid url")
                return false
            }
            return true
        case .openUrl:
            guard let url, let scheme = URL(string: url)?.scheme?.lowercased() else {
                warn(position, "open_url missing or invalid url")
                return false
            }
            guard openUrlAllowedSchemes.contains(scheme) else {
                warn(position, "open_url scheme '\(scheme)' is not allowed")
                return false
            }
            return true
        }
    }

    /// Absent, `null` and blank strings count as no value, matching Android's `optNonBlankString`.
    private static func isPresent(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let string = value as? String {
            return nonBlankString(string) != nil
        }
        return true
    }

    private static func nonBlankString(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }

    private static func warn(_ position: Int, _ reason: String) {
        if #available(iOS 14.0, *) {
            Logger.carousel.warning("Skipping carousel card \(position): \(reason)")
        }
    }
}
