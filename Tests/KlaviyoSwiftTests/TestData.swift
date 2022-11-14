//
//  TestData.swift
//  
//
//  Created by Noah Durell on 11/14/22.
//

import Foundation
import KlaviyoSwift

extension Klaviyo.Profile {
    static let test = Self.init(
        attributes: .test)
}

extension Klaviyo.Profile.Attributes {
    static let SAMPLE_PROPERTIES = [
        "blob": "blob",
        "stuff": 2,
        "hello": 4
    ] as [String : Any]
    static let test = Self.init(
        email: "blobemail",
        phoneNumber: "+15555555555",
        externalId: "blobid",
        firstName: "Blob",
        lastName: "Junior",
        organization: "Blobco",
        title: "Jelly",
        image: "foo",
        location: .test,
        properties: SAMPLE_PROPERTIES
    )
}

extension Klaviyo.Profile.Attributes.Location {
    static let test = Self.init(
        address1: "blob",
        address2: "blob",
        city: "blob city",
        country:"Blobland",
        latitude: 1,
        longitude: 1,
        region: "BL",
        zip: "0BLOB",
        timezone: "BLobTZ"
    )
    
}
