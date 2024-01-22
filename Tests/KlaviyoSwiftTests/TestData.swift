//
//  TestData.swift
//
//
//  Created by Noah Durell on 11/14/22.
//

import Foundation
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

let TEST_API_KEY = "fake-key"

let INITIALIZED_TEST_STATE = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        anonymousId: environment.analytics.uuid().uuidString,
        pushTokenData: .init(pushToken: "blob_token",
                             pushEnablement: .authorized,
                             pushBackground: .available,
                             deviceData: .init(context: environment.analytics.appContextInfo())),
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized,
        flushing: true)
}

let INITILIZING_TEST_STATE = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        anonymousId: environment.analytics.uuid().uuidString,
        queue: [],
        requestsInFlight: [],
        initalizationState: .initializing,
        flushing: true)
}

let INITIALIZED_TEST_STATE_INVALID_PHONE = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        anonymousId: environment.analytics.uuid().uuidString,
        phoneNumber: "invalid_phone_number",
        pushTokenData: .init(pushToken: "blob_token",
                             pushEnablement: .authorized,
                             pushBackground: .available,
                             deviceData: .init(context: environment.analytics.appContextInfo())),
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized,
        flushing: true)
}

let INITIALIZED_TEST_STATE_INVALID_EMAIL = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        email: "invalid_email",
        anonymousId: environment.analytics.uuid().uuidString,
        pushTokenData: .init(pushToken: "blob_token",
                             pushEnablement: .authorized,
                             pushBackground: .available,
                             deviceData: .init(context: environment.analytics.appContextInfo())),
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized,
        flushing: true)
}

extension Profile {
    static let SAMPLE_PROPERTIES = [
        "blob": "blob",
        "stuff": 2,
        "hello": [
            "sub": "dict"
        ]
    ] as [String: Any]
    static let test = Self(
        email: "blobemail",
        phoneNumber: "+15555555555",
        externalId: "blobid",
        firstName: "Blob",
        lastName: "Junior",
        organization: "Blobco",
        title: "Jelly",
        image: "foo",
        location: .test,
        properties: SAMPLE_PROPERTIES)
}

extension Profile.Location {
    static let test = Self(
        address1: "blob",
        address2: "blob",
        city: "blob city",
        country: "Blobland",
        latitude: 1,
        longitude: 1,
        region: "BL",
        zip: "0BLOB")
}

extension Event {
    static let SAMPLE_PROPERTIES = [
        "blob": "blob",
        "stuff": 2,
        "hello": [
            "sub": "dict"
        ],
        "Application ID": "com.klaviyo.fooapp",
        "App Version": "1.2.3",
        "App Build": "1",
        "App Name": "FooApp",
        "OS Version": "1.1.1",
        "OS Name": "iOS",
        "Device Manufacturer": "Orange",
        "Device Model": "jPhone 1,1"
    ] as [String: Any]
    static let SAMPLE_PROFILE_PROPERTIES = [
        "email": "blob@email.com",
        "stuff": 2,
        "location": [
            "city": "blob city"
        ]
    ] as [String: Any]
    static let test = Self(name: .CustomEvent("blob"), properties: SAMPLE_PROPERTIES, identifiers: .init(email: "blob@email.com"), profile: SAMPLE_PROFILE_PROPERTIES)
}

extension Event.Metric {
    static let test = Self(name: .CustomEvent("blob"))
}

extension KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload {
    static let test = Self(data: .init(event: .test))
}

extension URLResponse {
    static let non200Response = HTTPURLResponse(url: TEST_URL, statusCode: 500, httpVersion: nil, headerFields: nil)!
    static let validResponse = HTTPURLResponse(url: TEST_URL, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

extension KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload {
    static let test = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
        pushToken: "foo",
        enablement: "AUTHORIZED",
        background: "AVAILABLE",
        profile: .init(),
        anonymousId: "anon-id")
}

extension KlaviyoState {
    static let test = KlaviyoState(apiKey: "foo",
                                   email: "test@test.com",
                                   anonymousId: environment.analytics.uuid().uuidString,
                                   phoneNumber: "phoneNumber",
                                   externalId: "externalId",
                                   pushTokenData: .init(pushToken: "blob_token", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.analytics.appContextInfo())),
                                   queue: [],
                                   requestsInFlight: [],
                                   initalizationState: .initialized,
                                   flushing: true)
}

// MARK: - Legacy Stuff

let LEGACY_OPENED_PUSH = LegacyEvent(eventName: "$opened_push", customerProperties: [
    "$email": "blob@blob.com",
    "$id": "blobid",
    "foo": "bar"
], properties: ["baz": "boo"])

let LEGACY_PROFILE = LegacyProfile(customerProperties: [
    "$email": "blob@blob.com",
    "foo": "bar"
])
