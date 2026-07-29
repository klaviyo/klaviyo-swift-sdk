//
//  ProfileAPIExtension.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import Foundation
import KlaviyoCore

extension String {
    internal func trimWhiteSpaceOrReturnNilIfEmpty() -> String? {
        let trimmedString = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedString.isEmpty ? nil : trimmedString
    }

    /// Returns `true` when the trimmed string is non-empty and differs from the
    /// currently stored value. Emits a developer warning (and returns `false`)
    /// when the incoming value is empty or unchanged.
    internal func isNotEmptyOrSame(as state: String?, identifier: String) -> Bool {
        let incoming = trimmingCharacters(in: .whitespacesAndNewlines)
        if incoming.isEmpty || incoming == state {
            environment.emitDeveloperWarning("""
            \(identifier) is either empty or same as what is already set earlier.
            The SDK will ignore this change, please use resetProfile for
            resetting profile identifiers
            """)
        }

        return !incoming.isEmpty && incoming != state
    }
}

extension ProfilePayload {
    /// Builds the API profile payload from a ``Profile``, letting the caller override the identifiers
    /// (email, phone number, external ID) that are tracked separately on state.
    init(
        _ profile: Profile,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        anonymousId: String
    ) {
        self.init(
            email: email?.trimWhiteSpaceOrReturnNilIfEmpty() ?? profile.email?.trimWhiteSpaceOrReturnNilIfEmpty(),
            phoneNumber: phoneNumber?.trimWhiteSpaceOrReturnNilIfEmpty() ?? profile.phoneNumber?.trimWhiteSpaceOrReturnNilIfEmpty(),
            externalId: externalId?.trimWhiteSpaceOrReturnNilIfEmpty() ?? profile.externalId?.trimWhiteSpaceOrReturnNilIfEmpty(),
            firstName: profile.firstName,
            lastName: profile.lastName,
            organization: profile.organization,
            title: profile.title,
            image: profile.image,
            location: profile.location.map { Attributes.Location($0) },
            properties: profile.properties,
            anonymousId: anonymousId
        )
    }
}

extension ProfilePayload.Attributes.Location {
    /// Maps a ``Profile/Location`` to the API location object.
    init(_ location: Profile.Location) {
        self.init(
            address1: location.address1,
            address2: location.address2,
            city: location.city,
            country: location.country,
            latitude: location.latitude,
            longitude: location.longitude,
            region: location.region,
            zip: location.zip,
            timezone: location.timezone
        )
    }
}
