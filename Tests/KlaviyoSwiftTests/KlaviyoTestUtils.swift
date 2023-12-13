//
//  KlaviyoTestUtils.swift
//  KlaviyoSwiftTests
//
//  Created by Noah Durell on 9/30/22.
//
import AnyCodable
import Combine
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import CombineSchedulers

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

extension AppLifeCycleEvents {
    static let test = Self(lifeCycleEvents: { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() })
}

extension KlaviyoEnvironment {
    static var lastLog: String?
    static var test = { KlaviyoEnvironment(
        archiverClient: ArchiverClient.test,
        fileClient: FileClient.test,
        data: { _ in TEST_RETURN_DATA },
        logger: LoggerClient.test,
        analytics: AnalyticsEnvironment.test,
        getUserDefaultString: { _ in "value" },
        appLifeCycle: AppLifeCycleEvents.test,
        notificationCenterPublisher: { _ in Empty<Notification, Never>().eraseToAnyPublisher() },
        getNotificationSettings: { callback in callback(.authorized) },
        getBackgroundSetting: { .available },
        legacyIdentifier: { "iOS:\(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!.uuidString)" },
        startReachability: {},
        stopReachability: {},
        reachabilityStatus: { nil },
        randomInt: { 0 },
        stateChangePublisher: { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() },
        raiseFatalError: { _ in })
    }
}

class TestJSONDecoder: JSONDecoder {
    override func decode<T>(_: T.Type, from _: Data) throws -> T where T: Decodable {
        KlaviyoState.test as! T
    }
}

class InvalidJSONDecoder: JSONDecoder {
    override func decode<T>(_: T.Type, from _: Data) throws -> T where T: Decodable {
        throw KlaviyoDecodingError.invalidType
    }
}

extension AnalyticsEnvironment {
    static let testStore = Store(initialState: KlaviyoState(queue: []), reducer: KlaviyoReducer())

    static let test = AnalyticsEnvironment(
        networkSession: { NetworkSession.test() },
        apiURL: "dead_beef",
        encodeJSON: { _ in TEST_RETURN_DATA },
        decoder: DataDecoder(jsonDecoder: TestJSONDecoder()),
        uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
        date: { Date(timeIntervalSince1970: 1_234_567_890) },
        timeZone: { "EST" },
        appContextInfo: { AppContextInfo.test },
        klaviyoAPI: KlaviyoAPI.test(),
        timer: { _ in Just(Date()).eraseToAnyPublisher() },
        send: { action in
            testStore.send(action)
        },
        state: {
            AnalyticsEnvironment.testStore.state.value
        },
        statePublisher: {
            Just(INITIALIZED_TEST_STATE()).eraseToAnyPublisher()
        })
}

struct KlaviyoTestReducer: ReducerProtocol {
    var reducer: (inout KlaviyoSwift.KlaviyoState, KlaviyoAction) -> EffectTask<KlaviyoSwift.KlaviyoAction> = { _, _ in .none }

    func reduce(into state: inout KlaviyoSwift.KlaviyoState, action: KlaviyoSwift.KlaviyoAction) -> KlaviyoSwift.EffectTask<KlaviyoSwift.KlaviyoAction> {
        reducer(&state, action)
    }

    typealias State = KlaviyoState

    typealias Action = KlaviyoAction
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let test = Store(initialState: .test, reducer: KlaviyoTestReducer())
}

extension FileClient {
    static let test = FileClient(
        write: { _, _ in },
        fileExists: { _ in true },
        removeItem: { _ in },
        libraryDirectory: { TEST_URL })
}

extension KlaviyoAPI {
    static let test = { KlaviyoAPI(send: { _ in .success(TEST_RETURN_DATA) }) }
}

extension LoggerClient {
    static var lastLoggedMessage: String?
    static let test = LoggerClient { message in
        lastLoggedMessage = message
    }
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

extension StateChangePublisher {
    static let test = { () -> StateChangePublisher in
        StateChangePublisher.debouncedPublisher = { publisher in
            publisher
                .debounce(for: .seconds(0), scheduler: DispatchQueue.immediate)
                .eraseToAnyPublisher()
        }
        return Self()
    }()
}

private final class KeyedArchiver: NSKeyedArchiver {
    override func decodeObject(forKey _: String) -> Any { "" }
    override func decodeInt64(forKey _: String) -> Int64 { 0 }
}

extension UNNotificationResponse {
    static func with(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String = UNNotificationDefaultActionIdentifier) throws -> UNNotificationResponse {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        let request = UNNotificationRequest(
            identifier: "",
            content: content,
            trigger: nil)

        let notification = try XCTUnwrap(UNNotification(coder: KeyedArchiver(requiringSecureCoding: false)))
        notification.setValue(request, forKey: "request")

        let response = try XCTUnwrap(UNNotificationResponse(coder: KeyedArchiver(requiringSecureCoding: false)))
        response.setValue(notification, forKey: "notification")
        response.setValue(actionIdentifier, forKey: "actionIdentifier")
        return response
    }
}
