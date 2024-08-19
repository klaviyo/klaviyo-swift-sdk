//
//  TestData.swift
//
//
//  Created by Noah Durell on 11/14/22.
//

import Foundation
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import KlaviyoCore

let TEST_API_KEY = "fake-key"

let INITIALIZED_TEST_STATE = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        anonymousId: environment.uuid().uuidString,
        pushTokenData: .init(pushToken: "blob_token",
                             pushEnablement: .authorized,
                             pushBackground: .available,
                             deviceData: .init(context: environment.appContextInfo())),
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized,
        flushing: true)
}

let INITILIZING_TEST_STATE = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        anonymousId: environment.uuid().uuidString,
        queue: [],
        requestsInFlight: [],
        initalizationState: .initializing,
        flushing: true)
}

let INITIALIZED_TEST_STATE_INVALID_PHONE = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        anonymousId: environment.uuid().uuidString,
        phoneNumber: "invalid_phone_number",
        pushTokenData: .init(pushToken: "blob_token",
                             pushEnablement: .authorized,
                             pushBackground: .available,
                             deviceData: .init(context: environment.appContextInfo())),
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized,
        flushing: true)
}

let INITIALIZED_TEST_STATE_INVALID_EMAIL = {
    KlaviyoState(
        apiKey: TEST_API_KEY,
        email: "invalid_email",
        anonymousId: environment.uuid().uuidString,
        pushTokenData: .init(pushToken: "blob_token",
                             pushEnablement: .authorized,
                             pushBackground: .available,
                             deviceData: .init(context: environment.appContextInfo())),
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
        properties: [:])
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
    static let test = Self(name: .CustomEvent("blob"), properties: nil, time: KlaviyoEnvironment.test().date())
}

extension Event.Metric {
    static let test = Self(name: .CustomEvent("blob"))
}

extension KlaviyoState {
    static let test = KlaviyoState(apiKey: "foo",
                                   email: "test@test.com",
                                   anonymousId: environment.uuid().uuidString,
                                   phoneNumber: "phoneNumber",
                                   externalId: "externalId",
                                   pushTokenData: PushTokenData(
                                       pushToken: "blob_token",
                                       pushEnablement: .authorized,
                                       pushBackground: .available,
                                       deviceData: DeviceMetadata(context: environment.appContextInfo())),
                                   queue: [],
                                   requestsInFlight: [],
                                   initalizationState: .initialized,
                                   flushing: true)
}

let SAMPLE_DATA: NSMutableArray = [
    [
        "properties": [
            "foo": "bar"
        ]
    ]
]
let TEST_URL = URL(string: "fake_url")!
let TEST_RETURN_DATA = Data()

let TEST_FAILURE_JSON_INVALID_PHONE_NUMBER = """
{
    "errors": [
      {
        "id": "9997bd4f-7d5f-4f01-bbd1-df0065ef4faa",
        "status": 400,
        "code": "invalid",
        "title": "Invalid input.",
        "detail": "Invalid phone number format (Example of a valid format: +12345678901)",
        "source": {
          "pointer": "/data/attributes/phone_number"
        },
        "meta": {}
      }
    ]
}
"""

let TEST_FAILURE_JSON_INVALID_EMAIL = """
{
  "errors": [
    {
      "id": "dce2d180-0f36-4312-aa6d-92d025c17147",
      "status": 400,
      "code": "invalid",
      "title": "Invalid input.",
      "detail": "Invalid email address",
      "source": {
        "pointer": "/data/attributes/email"
      },
      "meta": {}
    }
  ]
}
"""
