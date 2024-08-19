//
//  TestUtils.swift
//
//
//  Created by Ajay Subramanya on 8/15/24.
//

import AnyCodable
import Combine
import Foundation
import KlaviyoCore

enum FakeFileError: Error {
    case fake
}

let ARCHIVED_RETURNED_DATA = Data()
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

extension ArchiverClient {
    static let test = ArchiverClient(
        archivedData: { _, _ in ARCHIVED_RETURNED_DATA },
        unarchivedMutableArray: { _ in SAMPLE_DATA })
}

extension KlaviyoEnvironment {
    static var lastLog: String?
    static var test = {
        KlaviyoEnvironment(
            archiverClient: ArchiverClient.test,
            fileClient: FileClient.test,
            dataFromUrl: { _ in TEST_RETURN_DATA },
            logger: LoggerClient.test,
            appLifeCycle: AppLifeCycleEvents.test,
            notificationCenterPublisher: { _ in Empty<Notification, Never>().eraseToAnyPublisher() },
            getNotificationSettings: { callback in callback(.authorized) },
            getBackgroundSetting: { .available },
            startReachability: {},
            stopReachability: {},
            reachabilityStatus: { nil },
            randomInt: { 0 },
            raiseFatalError: { _ in },
            emitDeveloperWarning: { _ in },
            networkSession: { NetworkSession.test() },
            apiURL: "dead_beef",
            encodeJSON: { _ in TEST_RETURN_DATA },
            decoder: DataDecoder(jsonDecoder: TestJSONDecoder()),
            uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
            date: { Date(timeIntervalSince1970: 1_234_567_890) },
            timeZone: { "EST" },
            appContextInfo: { AppContextInfo.test },
            klaviyoAPI: KlaviyoAPI.test(),
            timer: { _ in Just(Date()).eraseToAnyPublisher() })
    }
}

extension FileClient {
    static let test = FileClient(
        write: { _, _ in },
        fileExists: { _ in true },
        removeItem: { _ in },
        libraryDirectory: { TEST_URL })
}

extension KlaviyoAPI {
    static let test = { KlaviyoAPI(send: { _, _ in .success(TEST_RETURN_DATA) }) }
}

extension LoggerClient {
    static var lastLoggedMessage: String?
    static let test = LoggerClient { message in
        lastLoggedMessage = message
    }
}

extension AppLifeCycleEvents {
    static let test = Self(lifeCycleEvents: { Empty<LifeCycleEvents, Never>().eraseToAnyPublisher() })
}

extension NetworkSession {
    static let successfulRepsonse = HTTPURLResponse(url: TEST_URL, statusCode: 200, httpVersion: nil, headerFields: nil)!
    static let DEFAULT_CALLBACK: (URLRequest) async throws -> (Data, URLResponse) = { _ in
        (Data(), successfulRepsonse)
    }

    static func test(data: @escaping (URLRequest) async throws -> (Data, URLResponse) = DEFAULT_CALLBACK) -> NetworkSession {
        NetworkSession(data: data)
    }
}

class TestJSONDecoder: JSONDecoder {
    override func decode<T>(_: T.Type, from _: Data) throws -> T where T: Decodable {
        AppLifeCycleEvents.test as! T
    }
}

extension AppContextInfo {
    static let test = Self(executable: "FooApp",
                           bundleId: "com.klaviyo.fooapp",
                           appVersion: "1.2.3",
                           appBuild: "1",
                           appName: "FooApp",
                           version: OperatingSystemVersion(majorVersion: 1, minorVersion: 1, patchVersion: 1),
                           osName: "iOS",
                           manufacturer: "Orange",
                           deviceModel: "jPhone 1,1",
                           deviceId: "fe-fi-fo-fum")
}

extension URLResponse {
    static let non200Response = HTTPURLResponse(url: TEST_URL, statusCode: 500, httpVersion: nil, headerFields: nil)!
    static let validResponse = HTTPURLResponse(url: TEST_URL, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

extension PushTokenPayload {
    static let test = PushTokenPayload(
        pushToken: "foo",
        enablement: "AUTHORIZED",
        background: "AVAILABLE",
        profile: ProfilePayload(properties: [:], anonymousId: "anon-id"))
}

extension ProfilePayload {
    static let location = ProfilePayload.Attributes.Location(
        address1: "blob",
        address2: "blob",
        city: "blob city",
        country: "Blobland",
        latitude: 1,
        longitude: 1,
        region: "BL",
        zip: "0BLOB")

    static let test = ProfilePayload(
        email: "blobemail",
        phoneNumber: "+15555555555",
        externalId: "blobid",
        firstName: "Blob",
        lastName: "Junior",
        organization: "Blobco",
        title: "Jelly",
        image: "foo",
        location: location,
        properties: [:],
        anonymousId: "foo")
}
