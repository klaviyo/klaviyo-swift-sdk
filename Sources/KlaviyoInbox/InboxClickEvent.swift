//
//  InboxClickEvent.swift
//  klaviyo-swift-sdk
//

import Foundation
import KlaviyoCore
import OSLog

/// The metric and property names of a click event, kept together so they can change in one place.
enum InboxClickEvent {
    /// Branded under the `klaviyo` service. The name is also the metric key, so no backend mapping is
    /// needed for it to display.
    static let metricName = "Clicked App Inbox Message"
    static let service = "klaviyo"

    enum Property {
        static let transmissionID = "Inbox Transmission ID"
        static let message = "$message"
        static let messageType = "Message Type"
        static let messageName = "Message Name"
        static let actionType = "Action Type"
        static let actionURL = "Action URL"
        static let buttonLabel = "Button Label"

        /// Names the SDK owns. A custom property with one of these names is dropped, even when the SDK
        /// has no value for it on this click, so the same key always means the same thing.
        static let reserved: Set<String> = [
            transmissionID, message, messageType, messageName, actionType, actionURL, buttonLabel
        ]
    }

    /// Field limits the Events API enforces on a click event.
    enum Limit {
        static let transmissionID = 64
        static let actionURL = 2048
        static let buttonLabel = 255
    }

    /// Builds the click event for a tap on `message`.
    ///
    /// A button click reports `action`'s destination and label. A click without an action reports the
    /// message's default destination. The message's `$message`, `Message Type` and `Message Name` are
    /// copied from its stored `_k` when present.
    ///
    /// `properties` are added first and the SDK's own properties after them. A custom key that matches a
    /// built-in one is dropped, so it can never replace the SDK's value.
    ///
    /// Returns nil, and logs, when the message ID or action can't be reported within the API's limits, so
    /// a malformed click is dropped rather than rejected by the backend.
    static func make(
        message: InboxMessage,
        action: InboxAction?,
        properties custom: [String: Any] = [:]
    ) -> Event? {
        guard !message.id.isEmpty, message.id.count <= Limit.transmissionID else {
            log("Inbox click has an invalid message ID, ignoring")
            return nil
        }

        let destination = action?.destination ?? message.defaultDestination
        let url = destination.url?.absoluteString.nilIfEmpty

        if let url, url.count > Limit.actionURL {
            log("Inbox click action URL is too long, ignoring")
            return nil
        }

        let label = action?.label

        if let label, label.count > Limit.buttonLabel {
            log("Inbox click button label is too long, ignoring")
            return nil
        }

        var properties = custom.filter { !Property.reserved.contains($0.key) }
        properties[Property.transmissionID] = message.id
        properties[Property.actionType] = destination.type.rawValue
        if let url { properties[Property.actionURL] = url }
        if let label { properties[Property.buttonLabel] = label }

        // Each `_k` field is optional, so a push without one still produces a click.
        let attribution = attribution(of: message)
        if let value = attribution?[AttributionKey.message] { properties[Property.message] = value }
        if let value = attribution?[AttributionKey.messageType] { properties[Property.messageType] = value }
        if let value = attribution?[AttributionKey.messageName] { properties[Property.messageName] = value }

        // A fresh ID per click. It travels with the queued request, so a retry reuses it.
        return Event(
            name: .customEvent(metricName),
            properties: properties,
            uniqueId: UUID().uuidString,
            service: service
        )
    }

    /// The `_k` keys a click event copies from the message's attribution.
    private enum AttributionKey {
        static let message = "$message"
        static let messageType = "Message Type"
        static let messageName = "Message Name"
    }

    /// The non-blank string values of the message's stored `_k`, or nil when it has none or it can't be read.
    private static func attribution(of message: InboxMessage) -> [String: String]? {
        guard let data = message.attributionJSON else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("Unable to read inbox message attribution")
            return nil
        }
        return object.compactMapValues { ($0 as? String)?.nilIfEmpty }
    }

    private static func log(_ message: String) {
        if #available(iOS 14.0, *) {
            Logger.mobileInbox.warning("\(message, privacy: .public)")
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension MobileInbox {
    /// Reports a tap on a message or one of its buttons, as a **Clicked App Inbox Message** event.
    ///
    /// Call this when the user taps, separately from setting the message's state: a click never marks a
    /// message read or archived, and a state change never records a click. The SDK does not open the
    /// destination, so navigation stays with your app.
    ///
    /// The click is queued and sent with the rest of the SDK's analytics, so it is kept while offline and
    /// retried. It does not depend on the message still being stored.
    ///
    /// - Parameters:
    ///   - message: The message that was tapped.
    ///   - action: The button that was tapped, or nil for a tap on the message itself.
    ///   - properties: Extra properties to record on the event, such as which UI element the user tapped.
    ///     They are added last, so a key that matches one of the SDK's own properties, such as
    ///     `Action Type`, is ignored in favor of the SDK's value.
    public func trackMessageClick(
        _ message: InboxMessage,
        action: InboxAction? = nil,
        properties: [String: Any] = [:]
    ) {
        guard let event = InboxClickEvent.make(message: message, action: action, properties: properties) else {
            return
        }
        dispatchClick(event)
    }
}
