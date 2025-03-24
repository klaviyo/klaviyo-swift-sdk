//
//  ProfileAPIExtension.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import Foundation
import KlaviyoCore

extension String {
    fileprivate func trimWhiteSpaceOrReturnNilIfEmpty() -> String? {
        let trimmedString = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedString.isEmpty ? nil : trimmedString
    }
}

extension Profile {
    func toAPIModel(
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        anonymousId: String) -> ProfilePayload {
        ProfilePayload(
            email: email?.trimWhiteSpaceOrReturnNilIfEmpty() ?? self.email?.trimWhiteSpaceOrReturnNilIfEmpty(),
            phoneNumber: phoneNumber?.trimWhiteSpaceOrReturnNilIfEmpty() ?? self.phoneNumber?.trimWhiteSpaceOrReturnNilIfEmpty(),
            externalId: externalId?.trimWhiteSpaceOrReturnNilIfEmpty() ?? self.externalId?.trimWhiteSpaceOrReturnNilIfEmpty(),
            firstName: firstName,
            lastName: lastName,
            organization: organization,
            title: title,
            image: image,
            location: location?.toAPILocation,
            properties: properties,
            anonymousId: anonymousId)
    }
}

extension Profile.Location {
    var toAPILocation: ProfilePayload.Attributes.Location {
        ProfilePayload.Attributes.Location(
            address1: address1,
            address2: address2,
            city: city,
            country: country,
            latitude: latitude,
            longitude: longitude,
            region: region,
            zip: zip,
            timezone: timezone)
    }
}
