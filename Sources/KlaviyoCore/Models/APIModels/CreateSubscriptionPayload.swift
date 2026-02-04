//
//  CreateSubscriptionPayload.swift
//
//
//  Created by Reca on 2/4/26.
//

import Foundation

/// Payload structure for the Create Client Subscription API endpoint.
/// Used to subscribe a profile to email and/or SMS channels for a specific list.
public struct CreateSubscriptionPayload: Equatable, Codable {
    public let data: SubscriptionData

    public struct SubscriptionData: Equatable, Codable {
        var type = "subscription"
        public var attributes: Attributes

        public init(
            profile: ProfilePayload,
            listId: String,
            channels: SubscriptionChannels?,
            customSource: String = "iOS SDK"
        ) {
            attributes = Attributes(
                profile: Profile(data: profile),
                listId: listId,
                customSource: customSource,
                subscriptions: channels
            )
        }

        public struct Attributes: Equatable, Codable {
            public let profile: Profile
            public let listId: String
            public let customSource: String
            public let subscriptions: SubscriptionChannels?

            enum CodingKeys: String, CodingKey {
                case profile
                case listId = "list_id"
                case customSource = "custom_source"
                case subscriptions
            }

            public init(
                profile: Profile,
                listId: String,
                customSource: String,
                subscriptions: SubscriptionChannels?
            ) {
                self.profile = profile
                self.listId = listId
                self.customSource = customSource
                self.subscriptions = subscriptions
            }

            public struct Profile: Equatable, Codable {
                public let data: ProfilePayload

                public init(data: ProfilePayload) {
                    self.data = data
                }
            }
        }
    }

    public init(data: CreateSubscriptionPayload.SubscriptionData) {
        self.data = data
    }

    public init(
        profile: ProfilePayload,
        listId: String,
        channels: SubscriptionChannels?,
        customSource: String = "iOS SDK"
    ) {
        data = SubscriptionData(
            profile: profile,
            listId: listId,
            channels: channels,
            customSource: customSource
        )
    }
}

/// Represents the subscription channels and their consent settings.
public struct SubscriptionChannels: Equatable, Codable {
    public let email: ChannelConsent?
    public let sms: ChannelConsent?

    public init(email: ChannelConsent? = nil, sms: ChannelConsent? = nil) {
        self.email = email
        self.sms = sms
    }

    /// Convenience initializer for subscribing to specific channels with marketing consent.
    public static func marketing(email: Bool = false, sms: Bool = false) -> SubscriptionChannels? {
        let emailConsent = email ? ChannelConsent.marketing : nil
        let smsConsent = sms ? ChannelConsent.marketing : nil

        if emailConsent == nil && smsConsent == nil {
            return nil
        }

        return SubscriptionChannels(email: emailConsent, sms: smsConsent)
    }
}

/// Represents the consent settings for a single channel.
public struct ChannelConsent: Equatable, Codable {
    public let marketing: MarketingConsent

    public init(marketing: MarketingConsent) {
        self.marketing = marketing
    }

    /// Convenience for marketing consent.
    public static let marketing = ChannelConsent(marketing: MarketingConsent(consent: "MARKETING"))
}

/// Represents the marketing consent configuration.
public struct MarketingConsent: Equatable, Codable {
    public let consent: String

    public init(consent: String) {
        self.consent = consent
    }
}
