//
//  KlaviyoFormsTestUtils.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/6/25.
//

import Combine
import Foundation
import KlaviyoCore
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

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

let SAMPLE_PROPERTIES = [
    "Blob": "blob",
    "Stuff": 2,
    "Hello": [
        "Sub": "dict"
    ]
] as [String: Any]

extension ArchiverClient {
    static let test = ArchiverClient(
        archivedData: { _, _ in ARCHIVED_RETURNED_DATA },
        unarchivedMutableArray: { _ in SAMPLE_DATA }
    )
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
            getNotificationSettings: { .authorized },
            getBackgroundSetting: { .available },
            getBadgeAutoClearingSetting: { true },
            startReachability: {},
            stopReachability: {},
            reachabilityStatus: { nil },
            randomInt: { 0 },
            raiseFatalError: { _ in },
            emitDeveloperWarning: { _ in },
            networkSession: { NetworkSession.test() },
            apiURL: { URLComponents(string: "https://dead_beef")! },
            cdnURL: { URLComponents(string: "https://dead_beef")! },
            encodeJSON: { _ in TEST_RETURN_DATA },
            decoder: DataDecoder(jsonDecoder: TestJSONDecoder()),
            uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
            date: { Date(timeIntervalSince1970: 1_234_567_890) },
            timeZone: { "EST" },
            appContextInfo: { AppContextInfo.test },
            klaviyoAPI: KlaviyoAPI.test(),
            timer: { _ in Just(Date()).eraseToAnyPublisher() },
            SDKName: { __klaviyoSwiftName },
            SDKVersion: { __klaviyoSwiftVersion },
            formsDataEnvironment: { nil }
        )
    }
}

extension FileClient {
    static let test = FileClient(
        write: { _, _ in },
        fileExists: { _ in true },
        removeItem: { _ in },
        libraryDirectory: { TEST_URL }
    )
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

class TestJSONDecoder: JSONDecoder, @unchecked Sendable {
    override func decode<T>(_: T.Type, from _: Data) throws -> T where T: Decodable {
        KlaviyoState.test as! T
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
                                       deviceData: DeviceMetadata(context: environment.appContextInfo())
                                   ),
                                   queue: [],
                                   requestsInFlight: [],
                                   initalizationState: .initialized,
                                   flushing: true)
}
