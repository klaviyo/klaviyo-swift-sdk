//
//  Subscription.swift
//
//
//  Created by Aahil Nishad on 7/7/26.
//

/// A request to subscribe the current profile to a Klaviyo list and record its consent.
///
/// Pass a subscription to ``KlaviyoSDK/create(subscription:)``:
///
/// ```swift
/// // Email and SMS marketing, for whichever identifiers the profile has.
/// KlaviyoSDK().create(subscription: .allAvailableMarketing(listId: "LIST_ID"))
///
/// // Specific channels and consent types.
/// let subscription = Subscription(
///     listId: "LIST_ID",
///     channels: .init(email: .marketing, sms: [.marketing, .transactional]),
///     customSource: "Checkout Screen"
/// )
/// KlaviyoSDK().create(subscription: subscription)
/// ```
public struct Subscription: Equatable, Sendable {
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
    public struct Channels: Equatable, Sendable {
        /// Consent sub-types to request on the EMAIL channel.
        public let email: Email?
        /// Consent sub-types to request on the SMS channel.
        public let sms: Messaging?
        /// Consent sub-types to request on the WhatsApp channel.
        public let whatsapp: Messaging?

        /// Creates a set of channels to request consent for.
        ///
        /// Leave a channel `nil` to skip it. A channel that needs an email (EMAIL) or a phone
        /// number (SMS, WhatsApp) requires the profile to have that identifier.
        ///
        /// - Parameters:
        ///   - email: The consent types to request on the EMAIL channel.
        ///   - sms: The consent types to request on the SMS channel.
        ///   - whatsapp: The consent types to request on the WhatsApp channel.
        public init(email: Email? = nil, sms: Messaging? = nil, whatsapp: Messaging? = nil) {
            self.email = email
            self.sms = sms
            self.whatsapp = whatsapp
        }

        /// Consent sub-types supported on the EMAIL channel.
        public struct Email: OptionSet, Equatable, Sendable {
            /// The bit field of consent types.
            public let rawValue: Int
            /// Creates a set of email consent types from a bit field.
            /// - Parameter rawValue: The bit field. Prefer the static members.
            public init(rawValue: Int) { self.rawValue = rawValue }

            /// Email marketing consent.
            public static let marketing = Email(rawValue: 1 << 0)
            /// Email open-tracking consent.
            public static let openTracking = Email(rawValue: 1 << 1)
        }

        /// Consent sub-types supported on the SMS and WhatsApp channels.
        public struct Messaging: OptionSet, Equatable, Sendable {
            /// The bit field of consent types.
            public let rawValue: Int
            /// Creates a set of messaging consent types from a bit field.
            /// - Parameter rawValue: The bit field. Prefer the static members.
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
