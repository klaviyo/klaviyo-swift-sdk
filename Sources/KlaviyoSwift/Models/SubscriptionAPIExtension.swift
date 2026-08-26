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
}

extension EmailConsent {
    /// Maps the requested EMAIL sub-types to the API consent object, or `nil` when none were named.
    init?(_ options: Subscription.Channels.Email) {
        guard !options.isEmpty else { return nil }
        self.init(
            marketing: options.contains(.marketing) ? .subscribed : nil,
            openTracking: options.contains(.openTracking) ? .subscribed : nil
        )
    }
}

extension MarketingTransactionalConsent {
    /// Maps the requested SMS/WhatsApp sub-types to the API consent object, or `nil` when none were named.
    init?(_ options: Subscription.Channels.Messaging) {
        guard !options.isEmpty else { return nil }
        self.init(
            marketing: options.contains(.marketing) ? .subscribed : nil,
            transactional: options.contains(.transactional) ? .subscribed : nil
        )
    }
}

extension SubscriptionChannels {
    /// Maps the requested channels to the API's `subscriptions` object, or `nil` when no sub-types
    /// were named (nothing to send).
    init?(_ channels: Subscription.Channels) {
        let email = channels.email.flatMap(EmailConsent.init)
        let sms = channels.sms.flatMap(MarketingTransactionalConsent.init)
        let whatsapp = channels.whatsapp.flatMap(MarketingTransactionalConsent.init)
        guard email != nil || sms != nil || whatsapp != nil else { return nil }
        self.init(email: email, sms: sms, whatsapp: whatsapp)
    }
}
