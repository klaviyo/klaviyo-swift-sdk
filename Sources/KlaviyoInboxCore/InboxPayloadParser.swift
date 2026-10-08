//
//  InboxPayloadParser.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation

/// Normalizes a delivered Klaviyo push `userInfo` into an `InboxRecord`. Pure and total: it never
/// throws, and anything it cannot read becomes `nil` or is skipped.
package enum InboxPayloadParser {
    package static let maxActions = 3

    private enum Key {
        static let aps = "aps"
        static let alert = "alert"
        static let title = "title"
        static let body = "body"
        static let metadata = "_k"
        static let transmissionID = "tm"
        static let timestamp = "timestamp"
        static let url = "url"
        static let webURL = "web_url"
        static let richMedia = "rich-media"
        static let richMediaType = "rich-media-type"
        static let keyValuePairs = "key_value_pairs"
        static let actionButtons = "action_buttons"
        static let id = "id"
        static let label = "label"
        static let action = "action"
    }

    /// Whether the payload carries Klaviyo `_k` metadata, regardless of whether it is usable.
    package static func hasKlaviyoMetadata(_ userInfo: [AnyHashable: Any]) -> Bool {
        klaviyoMetadata(in: userInfo) != nil
    }

    /// `nil` when the payload is not a Klaviyo push or has no usable `_k.tm` (the dedup key).
    package static func parse(userInfo: [AnyHashable: Any], receivedAt: Date) -> InboxRecord? {
        guard let metadata = klaviyoMetadata(in: userInfo),
              let transmissionID = InboxPayload.string(metadata[Key.transmissionID]),
              !transmissionID.isEmpty else {
            return nil
        }
        let payload = InboxPayload.dictionary(userInfo) ?? [:]
        let alert = alertText(from: InboxPayload.dictionary(payload[Key.aps]))

        return InboxRecord(
            attribution: InboxAttribution(
                transmissionID: transmissionID,
                rawProperties: InboxPayload.snapshot(metadata)
            ),
            title: alert.title,
            body: alert.body,
            defaultDestination: defaultDestination(from: payload),
            mediaURL: InboxPayload.string(payload[Key.richMedia]).flatMap { URL(string: $0) },
            mediaType: InboxPayload.string(payload[Key.richMediaType]),
            customData: customData(from: payload[Key.keyValuePairs]),
            actions: actions(from: InboxPayload.dictionary(payload[Key.body])),
            sentAt: InboxPayload.date(metadata[Key.timestamp]),
            receivedAt: receivedAt
        )
    }

    // MARK: - Private

    private static func klaviyoMetadata(in userInfo: [AnyHashable: Any]) -> [String: Any]? {
        let payload = InboxPayload.dictionary(userInfo)
        let body = InboxPayload.dictionary(payload?[Key.body])
        return InboxPayload.dictionary(body?[Key.metadata])
    }

    private static func alertText(from aps: [String: Any]?) -> (title: String?, body: String?) {
        let alert = aps?[Key.alert]
        if let text = alert as? String { return (nil, text) }
        let dictionary = InboxPayload.dictionary(alert)
        let title = InboxPayload.string(dictionary?[Key.title])
        let body = InboxPayload.string(dictionary?[Key.body])
        return (title, body)
    }

    private static func defaultDestination(from payload: [String: Any]) -> InboxDestination {
        if let string = InboxPayload.string(payload[Key.url]), !string.isEmpty,
           let url = URL(string: string) {
            return .deepLink(url)
        }
        if let string = InboxPayload.string(payload[Key.webURL]), !string.isEmpty,
           let url = URL(string: string), InboxURLSchemeAllowlist.isAllowed(url) {
            return .openUrl(url)
        }
        return .openApp
    }

    private static func customData(from value: Any?) -> [String: String] {
        guard let dictionary = InboxPayload.dictionary(value) else { return [:] }
        var result: [String: String] = [:]
        for (key, element) in dictionary {
            if let string = InboxPayload.stringified(element) { result[key] = string }
        }
        return result
    }

    private static func actions(from body: [String: Any]?) -> [InboxAction] {
        guard let entries = body?[Key.actionButtons] as? [Any] else { return [] }
        var result: [InboxAction] = []
        for entry in entries {
            guard result.count < maxActions else { break }
            guard let button = InboxPayload.dictionary(entry),
                  let id = InboxPayload.string(button[Key.id]), !id.isEmpty,
                  let label = InboxPayload.string(button[Key.label]), !label.isEmpty,
                  let action = InboxPayload.string(button[Key.action]),
                  let destination = destination(action: action, url: InboxPayload.string(button[Key.url]))
            else { continue }
            result.append(InboxAction(id: id, label: label, destination: destination))
        }
        return result
    }

    /// `nil` drops the button. Unknown action types are kept: they carry no URL semantics to validate.
    private static func destination(action: String, url: String?) -> InboxDestination? {
        guard let type = InboxActionType(rawValue: action) else { return .unknown(action) }
        switch type {
        case .openApp:
            return url == nil ? .openApp : nil
        case .deepLink:
            return url.flatMap { URL(string: $0) }.map(InboxDestination.deepLink)
        case .openUrl:
            guard let url = url.flatMap({ URL(string: $0) }), InboxURLSchemeAllowlist.isAllowed(url) else {
                return nil
            }
            return .openUrl(url)
        }
    }
}
