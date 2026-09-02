//
//  SubscriptionChannels.swift
//
//
//  Created by Aahil Nishad on 7/14/26.
//

import Foundation

/// `subscriptions` object on a profile: one entry per channel. Each channel exposes only the consent
/// sub-types the API supports for it — email: `marketing` + `open_tracking`; SMS and WhatsApp:
/// `marketing` + `transactional`. Every consent value is `{ "consent": "SUBSCRIBED" }`.
public struct SubscriptionChannels: Equatable, Codable {
    public let email: EmailConsent?
    public let sms: MarketingTransactionalConsent?
    public let whatsapp: MarketingTransactionalConsent?

    public init(
        email: EmailConsent? = nil,
        sms: MarketingTransactionalConsent? = nil,
        whatsapp: MarketingTransactionalConsent? = nil
    ) {
        self.email = email
        self.sms = sms
        self.whatsapp = whatsapp
    }
}

public struct SubscriptionConsent: Equatable, Codable {
    public let consent: String

    private init(consent: String) {
        self.consent = consent
    }

    public static let subscribed = SubscriptionConsent(
        consent: "SUBSCRIBED"
    )
}

/// EMAIL channel consent: `marketing` and/or `open_tracking`.
public struct EmailConsent: Equatable, Codable {
    public let marketing: SubscriptionConsent?
    public let openTracking: SubscriptionConsent?

    enum CodingKeys: String, CodingKey {
        case marketing
        case openTracking = "open_tracking"
    }

    public init(
        marketing: SubscriptionConsent? = nil,
        openTracking: SubscriptionConsent? = nil
    ) {
        self.marketing = marketing
        self.openTracking = openTracking
    }
}

/// SMS and WhatsApp channel consent: `marketing` and/or `transactional`.
public struct MarketingTransactionalConsent: Equatable, Codable {
    public let marketing: SubscriptionConsent?
    public let transactional: SubscriptionConsent?

    public init(
        marketing: SubscriptionConsent? = nil,
        transactional: SubscriptionConsent? = nil
    ) {
        self.marketing = marketing
        self.transactional = transactional
    }
}
