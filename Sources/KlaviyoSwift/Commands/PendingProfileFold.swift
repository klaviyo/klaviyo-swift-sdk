//
//  PendingProfileFold.swift
//
//
//  Created by Isobelle Lim on 9/11/26.
//

import AnyCodable
import KlaviyoCore

/// State-free helpers for folding a staged profile (from `setProfileProperty`) into an existing
/// `CreateProfilePayload`. Used by the `ProfilePropertyBuffer` drain path to merge staged properties
/// into the outbound request with no `self` dependency.
enum PendingProfileFold {
    /// Merges a pending profile's attributes into the request. Scalar fields (name, title,
    /// organization, image) are PRESERVED — an existing value on the request wins. `properties` is
    /// merged key-by-key, giving precedence to the PENDING value on duplicate keys.
    static func mergePendingAttributes(
        from pending: Profile,
        into attributes: inout ProfilePayload.Attributes
    ) {
        if let firstName = pending.firstName {
            attributes.firstName = attributes.firstName ?? firstName
        }
        if let lastName = pending.lastName {
            attributes.lastName = attributes.lastName ?? lastName
        }
        if let title = pending.title {
            attributes.title = attributes.title ?? title
        }
        if let organization = pending.organization {
            attributes.organization = attributes.organization ?? organization
        }
        if let image = pending.image {
            attributes.image = attributes.image ?? image
        }
        if !pending.properties.isEmpty {
            let existing = attributes.properties.value as? [String: Any] ?? [:]
            attributes.properties = AnyCodable(
                existing.merging(pending.properties, uniquingKeysWith: { _, newer in newer })
            )
        }
    }

    /// Fills in location fields from a pending profile without overwriting values already present.
    static func mergedLocation(
        from pending: Profile,
        into location: ProfilePayload.Attributes.Location
    ) -> ProfilePayload.Attributes.Location {
        var location = location
        if let address1 = pending.location?.address1 {
            location.address1 = location.address1 ?? address1
        }
        if let address2 = pending.location?.address2 {
            location.address2 = location.address2 ?? address2
        }
        if let city = pending.location?.city {
            location.city = location.city ?? city
        }
        if let region = pending.location?.region {
            location.region = location.region ?? region
        }
        if let country = pending.location?.country {
            location.country = location.country ?? country
        }
        if let zipCode = pending.location?.zip {
            location.zip = location.zip ?? zipCode
        }
        if let latitude = pending.location?.latitude {
            location.latitude = location.latitude ?? latitude
        }
        if let longitude = pending.location?.longitude {
            location.longitude = location.longitude ?? longitude
        }
        return location
    }
}
