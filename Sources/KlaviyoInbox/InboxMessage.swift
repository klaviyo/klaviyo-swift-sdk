//
//  InboxMessage.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation

/// What a tap on a message or one of its buttons does. The host performs the navigation; the SDK never
/// opens a destination on its own.
///
/// Raw-value structs rather than enums, so a later release can add a value without breaking a host's
/// exhaustive `switch`.
public struct InboxDestinationType: Hashable, Sendable {
    public let rawValue: String

    /// Open the app with no further navigation.
    public static let openApp = InboxDestinationType(rawValue: "open_app")
    /// Route ``InboxDestination/url`` through the app's deep link handling.
    public static let deepLink = InboxDestinationType(rawValue: "deep_link")
    /// Open ``InboxDestination/url``, one of the schemes the SDK allows for action buttons.
    public static let openUrl = InboxDestinationType(rawValue: "open_url")
}

/// Where a message or button leads.
public struct InboxDestination: Hashable, Sendable {
    public let type: InboxDestinationType
    /// Nil for ``InboxDestinationType/openApp``.
    public let url: URL?
}

/// A button on a message.
public struct InboxAction: Hashable, Sendable {
    /// Identifies the selected button for metrics.
    public let id: String
    public let label: String
    public let destination: InboxDestination
}

/// Where a message came from. A raw-value struct so a later release can add a source, such as a
/// server-fetched record, without breaking a host's exhaustive `switch`.
public struct InboxMessageSource: Hashable, Sendable {
    public let rawValue: String

    /// Captured on this device from a delivered push.
    public static let captured = InboxMessageSource(rawValue: "captured")
    public static let server = InboxMessageSource(rawValue: "server")
    public static let external = InboxMessageSource(rawValue: "external")
}

/// The badge instructions a push carried. Parsed and kept for the host to read; the inbox's own unread
/// count is separate. Every value is optional because a push sets only some of them.
public struct InboxBadge: Hashable, Sendable {
    /// `aps.badge`.
    public let apsBadge: Int?
    /// The Klaviyo badge configuration, such as `set_count`.
    public let config: String?
    public let value: Int?
    /// `notification_count`.
    public let notificationCount: Int?
}

/// A message in the inbox.
public struct InboxMessage: Hashable, Sendable {
    /// Opaque. Stable for the life of the message.
    public let id: String
    public let title: String?
    public let body: String?
    /// What tapping the message does.
    public let defaultDestination: InboxDestination
    /// The host downloads and caches the media. Only the URL is stored.
    public let mediaURL: URL?
    public let mediaType: String?
    public let customData: [String: String]
    /// In the order the push configured them.
    public let actions: [InboxAction]
    /// Server send time, when known.
    public let sentAt: Date?
    /// When this device captured the push.
    public let receivedAt: Date
    /// Only populated where the platform exposes it reliably. iOS does not expose `apns-collapse-id` to
    /// the extension, so this is nil until the payload carries one.
    public let collapseID: String?
    public let badge: InboxBadge?
    public let isRead: Bool
    public let isArchived: Bool
    public let source: InboxMessageSource
}
