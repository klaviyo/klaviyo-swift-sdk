//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import Foundation
import KlaviyoCore

extension String {
    fileprivate func returnNilIfEmpty() -> String? {
        isEmpty ? nil : self
    }
}

extension Profile {
    func toAPIModel(
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        anonymousId: String) -> ProfilePayload {
        ProfilePayload(
            email: email ?? self.email?.returnNilIfEmpty(),
            phoneNumber: phoneNumber ?? self.phoneNumber?.returnNilIfEmpty(),
            externalId: externalId ?? self.externalId?.returnNilIfEmpty(),
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
            zip: self.zip,
            timezone: timezone)
    }
}
