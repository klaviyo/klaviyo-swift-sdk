//
//  SubscriptionAPIExtension.swift
//
//
//  Created by Aahil Nishad on 7/14/26.
//

import Foundation
import KlaviyoCore

extension Subscription.Channels {
    /// Whether the requested channels need an email identifier on the profile.
    var needsEmail: Bool {
        email?.isEmpty == false
    }

    /// Whether the requested channels need a phone number identifier on the profile.
    var needsPhone: Bool {
        sms?.isEmpty == false || whatsapp?.isEmpty == false
    }

    /// Maps the requested channels to the API's `subscriptions` object, or `nil` when no sub-types
    /// were named (nothing to send).
    var toAPIModel: SubscriptionChannels? {
        let emailConsent = email.flatMap { set -> EmailConsent? in
            guard !set.isEmpty else { return nil }
            return EmailConsent(
                marketing: set.contains(.marketing) ? .subscribed : nil,
                openTracking: set.contains(.openTracking) ? .subscribed : nil
            )
        }
        let smsConsent = messagingConsent(sms)
        let whatsappConsent = messagingConsent(whatsapp)

        guard emailConsent != nil || smsConsent != nil || whatsappConsent != nil else { return nil }
        return SubscriptionChannels(email: emailConsent, sms: smsConsent, whatsapp: whatsappConsent)
    }

    private func messagingConsent(_ set: Messaging?) -> MarketingTransactionalConsent? {
        guard let set, !set.isEmpty else { return nil }
        return MarketingTransactionalConsent(
            marketing: set.contains(.marketing) ? .subscribed : nil,
            transactional: set.contains(.transactional) ? .subscribed : nil
        )
    }
}
