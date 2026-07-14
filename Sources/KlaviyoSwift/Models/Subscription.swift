//
//  Subscription.swift
//
//
//  Created by Aahil Nishad on 7/7/26.
//

import Foundation

/// Represents a subscription request to subscribe a profile to a Klaviyo list.
public struct Subscription: Equatable {
    /// The ID of the Klaviyo list to subscribe the profile to.
    public let listId: String

    /// The channels to request consent for, or `nil` to defer to the server's default of MARKETING
    /// consent on every identified channel. `nil` is only reachable through
    /// ``allAvailableMarketing(listId:customSource:)`` — the public initializer requires channels so a
    /// broad grant is never the result of an omitted argument.
    public let channels: Channels?

    /// Free-text label describing where this signup originated (e.g. a form or screen name).
    /// Stored as the consent record's `$source`, pass an explicit value to override, or `nil` to omit it entirely.
    public let customSource: String?

    /// The channels to request consent for. Mirrors the API's `subscriptions` object: each channel
    /// exposes only the consent sub-types it supports, so invalid combinations (transactional email,
    /// open-tracking SMS) don't compile. Combine sub-types with array-literal syntax, e.g.
    /// `.init(sms: [.marketing, .transactional])`.
    public struct Channels: Equatable {
        /// Consent sub-types to request on the EMAIL channel.
        public let email: Email?
        /// Consent sub-types to request on the SMS channel.
        public let sms: Messaging?
        /// Consent sub-types to request on the WhatsApp channel.
        public let whatsapp: Messaging?

        public init(email: Email? = nil, sms: Messaging? = nil, whatsapp: Messaging? = nil) {
            self.email = email
            self.sms = sms
            self.whatsapp = whatsapp
        }

        /// Consent sub-types supported on the EMAIL channel.
        public struct Email: OptionSet, Equatable {
            public let rawValue: Int
            public init(rawValue: Int) { self.rawValue = rawValue }

            /// Email marketing consent.
            public static let marketing = Email(rawValue: 1 << 0)
            /// Email open-tracking consent.
            public static let openTracking = Email(rawValue: 1 << 1)
        }

        /// Consent sub-types supported on the SMS and WhatsApp channels.
        public struct Messaging: OptionSet, Equatable {
            public let rawValue: Int
            public init(rawValue: Int) { self.rawValue = rawValue }

            /// Marketing consent.
            public static let marketing = Messaging(rawValue: 1 << 0)
            /// Transactional messaging consent.
            public static let transactional = Messaging(rawValue: 1 << 1)
        }
    }

    /// Creates a subscription request for the given channels.
    /// - Parameters:
    ///   - listId: The ID of the Klaviyo list to subscribe the profile to.
    ///   - channels: The channels and sub-types to request consent for.
    ///   - customSource: Optional signup-source label stored as the consent record's `$source`.
    ///     Omitted from the request when `nil` (the default).
    public init(listId: String, channels: Channels, customSource: String? = nil) {
        self.init(listId: listId, channels: .some(channels), customSource: customSource)
    }

    private init(listId: String, channels: Channels?, customSource: String?) {
        self.listId = listId
        self.channels = channels
        self.customSource = customSource
    }

    /// Creates a subscription that grants MARKETING consent on every channel the profile has an
    /// identifier for (email → email marketing, phone → SMS marketing). Mirrors the server's default
    /// behavior when no `subscriptions` object is sent, but requesting it is a deliberate call.
    /// - Parameters:
    ///   - listId: The ID of the Klaviyo list to subscribe the profile to.
    ///   - customSource: Optional signup-source label stored as the consent record's `$source`.
    public static func allAvailableMarketing(listId: String, customSource: String? = nil) -> Subscription {
        Subscription(listId: listId, channels: nil, customSource: customSource)
    }
}
