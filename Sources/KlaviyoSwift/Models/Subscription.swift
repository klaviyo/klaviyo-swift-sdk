//
//  Subscription.swift
//
//
//  Created by Reca on 2/4/26.
//

import Foundation

/// Represents a subscription request to subscribe a profile to a Klaviyo list.
public struct Subscription: Equatable {
    /// The ID of the Klaviyo list to subscribe the profile to.
    public let listId: String

    /// The subscription channels to request consent for.
    /// If nil, the API will default to MARKETING consent for all available channels
    /// based on the profile identifiers (email for email channel, phone for SMS).
    public let channels: Channels?

    /// Represents the subscription channels configuration.
    public struct Channels: Equatable {
        /// Whether to subscribe to email marketing.
        public let email: Bool

        /// Whether to subscribe to SMS marketing.
        public let sms: Bool

        /// Creates a subscription channels configuration.
        /// - Parameters:
        ///   - email: Whether to subscribe to email marketing. Default is false.
        ///   - sms: Whether to subscribe to SMS marketing. Default is false.
        public init(email: Bool = false, sms: Bool = false) {
            self.email = email
            self.sms = sms
        }

        /// Convenience for email-only subscription.
        public static let emailOnly = Channels(email: true, sms: false)

        /// Convenience for SMS-only subscription.
        public static let smsOnly = Channels(email: false, sms: true)

        /// Convenience for both email and SMS subscription.
        public static let both = Channels(email: true, sms: true)
    }

    /// Creates a subscription request.
    /// - Parameters:
    ///   - listId: The ID of the Klaviyo list to subscribe the profile to.
    ///   - channels: The channels to subscribe to. If nil, defaults to all available channels.
    public init(listId: String, channels: Channels? = nil) {
        self.listId = listId
        self.channels = channels
    }
}
