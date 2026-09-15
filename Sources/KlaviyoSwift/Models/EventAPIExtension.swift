//
//  EventAPIExtension.swift
//
//  Klaviyo Swift SDK
//
//  Created by Belle Lim on 7/20/26.
//

import Foundation
import KlaviyoCore

extension Event {
    /// Returns a copy of the event stamped with the given profile identifiers.
    /// For opened-push events, the push token (when present) is added to the
    /// event properties.
    func updateEventWithIdentifiers(
        email: String?,
        phoneNumber: String?,
        externalId: String?,
        pushToken: String?
    ) -> Event {
        let identifiers = Identifiers(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId
        )
        var properties = properties
        if metric.name == EventName._openedPush,
           let pushToken {
            properties["push_token"] = pushToken
        }
        return Event(name: metric.name,
                     properties: properties,
                     identifiers: identifiers,
                     value: value,
                     time: time,
                     uniqueId: uniqueId)
    }
}
