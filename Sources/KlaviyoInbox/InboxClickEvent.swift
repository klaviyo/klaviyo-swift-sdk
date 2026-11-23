//
//  InboxClickEvent.swift
//  klaviyo-swift-sdk
//

import Foundation
import KlaviyoCore
import OSLog

/// The part of a message the user tapped.
///
/// A raw-value struct rather than an enum, so a later release can add a value without breaking a host's
/// exhaustive `switch`.
public struct InboxClickElement: Hashable, Sendable {
    public let rawValue: String

    /// The message itself, which performs ``InboxMessage/defaultDestination``.
    public static let body = InboxClickElement(rawValue: "body")
    /// One of the message's ``InboxMessage/actions``.
    public static let button = InboxClickElement(rawValue: "button")
}

/// The metric and property names of a click event, kept together so they can change in one place.
enum InboxClickEvent {
    /// Branded under the `klaviyo` service. The name is also the metric key, so no backend mapping is
    /// needed for it to display.
    static let metricName = "Clicked App Inbox Message"
    static let service = "klaviyo"

    // Pending product: the key for the push transmission ID may be renamed. The candidates are
    // "$message", as other push events use, or "id", as the inbox API uses.
    enum Property {
        static let messageID = "Inbox Message ID"
        static let actionType = "Action Type"
        static let actionURL = "Action URL"
        static let element = "Element"
        static let buttonLabel = "Button Label"
    }

    /// Field limits the Events API enforces on a click event.
    enum Limit {
        static let messageID = 64
        static let actionURL = 2048
        static let buttonLabel = 255
    }

    /// Builds the click event for a tap on `message`.
    ///
    /// A button click reports `action`'s destination and label. A body click reports the message's
    /// default destination. Returns nil, and logs, when the message ID or action can't be reported within
    /// the API's limits, so a malformed click is dropped rather than rejected by the backend.
    ///
    /// - Parameter element: Which part of the message was tapped. Defaults to a button when `action` is
    ///   given, otherwise the body.
    static func make(message: InboxMessage, action: InboxAction?, element: InboxClickElement?) -> Event? {
        let clicked = element ?? (action != nil ? .button : .body)
        let isButton = clicked == .button

        if isButton, action == nil {
            log("Inbox click on a button without an action, ignoring")
            return nil
        }

        guard !message.id.isEmpty, message.id.count <= Limit.messageID else {
            log("Inbox click has an invalid message ID, ignoring")
            return nil
        }

        let destination = isButton ? action?.destination : message.defaultDestination
        let url = destination?.url?.absoluteString.nilIfEmpty

        if let url, url.count > Limit.actionURL {
            log("Inbox click action URL is too long, ignoring")
            return nil
        }

        let label = isButton ? action?.label : nil

        if let label, label.count > Limit.buttonLabel {
            log("Inbox click button label is too long, ignoring")
            return nil
        }

        var properties: [String: Any] = [
            Property.messageID: message.id,
            Property.element: clicked.rawValue
        ]
        if let destination { properties[Property.actionType] = destination.type.rawValue }
        if let url { properties[Property.actionURL] = url }
        if let label { properties[Property.buttonLabel] = label }

        // A fresh ID per click. It travels with the queued request, so a retry reuses it.
        return Event(
            name: .customEvent(metricName),
            properties: properties,
            uniqueId: UUID().uuidString,
            service: service
        )
    }

    private static func log(_ message: String) {
        if #available(iOS 14.0, *) {
            Logger.mobileInbox.warning("\(message, privacy: .public)")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
    ///   - element: Which part of the message was tapped. Defaults to ``InboxClickElement/button`` when
    ///     `action` is given, otherwise ``InboxClickElement/body``.
    public func trackMessageClick(
        _ message: InboxMessage,
        action: InboxAction? = nil,
        element: InboxClickElement? = nil
    ) {
        guard let event = InboxClickEvent.make(message: message, action: action, element: element) else { return }
        dispatchClick(event)
    }
}
