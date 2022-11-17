//
//  TestData.swift
//  
//
//  Created by Noah Durell on 11/14/22.
//

import Foundation
@testable import KlaviyoSwift

extension Klaviyo.Profile {
    static let test = Self.init(
        attributes: .test)
}

extension Klaviyo.Profile.Attributes {
    static let SAMPLE_PROPERTIES = [
        "blob": "blob",
        "stuff": 2,
        "hello": [
            "sub": "dict"
        ]
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

extension Klaviyo.Event {
    static let test = Self.init(attributes: .test)
}

extension Klaviyo.Event.Attributes {
    static let SAMPLE_PROPERTIES = [
        "blob": "blob",
        "stuff": 2,
        "hello": [
            "sub": "dict"
        ]
    ] as [String : Any]
    static let SAMPLE_PROFILE_PROPERTIES = [
        "email": "blob@email.com",
        "stuff": 2,
        "location": [
            "city": "blob city"
        ]
    ] as [String : Any]
    static let test = Self.init(metric: .test, properties: SAMPLE_PROPERTIES, profile: SAMPLE_PROFILE_PROPERTIES)
}

extension Klaviyo.Event.Attributes.Metric {
    static let test = Self.init(name: "blob", service: "blob service")
}

extension KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload {
    
    static let test = Self.init(data: .test)
}

extension URLResponse {
    static let non200Response = HTTPURLResponse(url: TEST_URL, statusCode: 500, httpVersion: nil, headerFields: nil)
    static let validResponse = HTTPURLResponse(url: TEST_URL, statusCode: 200, httpVersion: nil, headerFields: nil)
}

extension KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload {
    static let test = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload.init(token: "foo", properties: Properties(anonymousId: "anon-id", pushToken: "foo"))
}

