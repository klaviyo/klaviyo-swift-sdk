//
//  KlaviyoTestUtils.swift
//  KlaviyoSwiftTests
//
//  Created by Noah Durell on 9/30/22.
//
import XCTest
@testable import KlaviyoSwift
import AnyCodable
import Combine

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

extension ArchiverClient {
    static let test = ArchiverClient(
        archivedData: { _, _ in ARCHIVED_RETURNED_DATA },
        unarchivedMutableArray: { _ in SAMPLE_DATA }
    )
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
        getUserDefaultString: { _ in return "value" },
        appLifeCycle: AppLifeCycleEvents.test,
        notificationCenterPublisher: { _ in Empty<Notification, Never>().eraseToAnyPublisher() },
        legacyIdentifier: { "iOS:\(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!.uuidString)"  },
        startReachability: {},
        stopReachability: {},
        reachabilityStatus: { nil },
        randomInt: { 0 },
        stateChangePublisher: { Empty<KlaviyoAction, Never>().eraseToAnyPublisher() }
    )
    }
}

class TestJSONDecoder: JSONDecoder {
    override func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable {
        return KlaviyoState.test as! T
    }
}

class InvalidJSONDecoder: JSONDecoder {
    override func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable {
        throw KlaviyoDecodingError.invalidType
    }
}

extension AnalyticsEnvironment {
    static let test = AnalyticsEnvironment(
        networkSession: { NetworkSession.test() },
        apiURL: "dead_beef",
        encodeJSON: { _ in TEST_RETURN_DATA},
        decoder: DataDecoder(jsonDecoder: TestJSONDecoder()),
        uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
        date: { Date(timeIntervalSince1970: 1_234_567_890) },
        timeZone: { "EST" },
        appContextInfo: { AppContextInfo.test },
        klaviyoAPI: KlaviyoAPI.test(),
        store: Store.test,
        timer: { interval in Just(Date()).eraseToAnyPublisher() }
    )
}

struct KlaviyoTestReducer: ReducerProtocol {
    var reducer: (inout KlaviyoSwift.KlaviyoState, KlaviyoAction) -> EffectTask<KlaviyoSwift.KlaviyoAction> = { _, _ in return .none }
    
    func reduce(into state: inout KlaviyoSwift.KlaviyoState, action: KlaviyoSwift.KlaviyoAction) -> KlaviyoSwift.EffectTask<KlaviyoSwift.KlaviyoAction> {
        return reducer(&state, action)
    }
    
    typealias State = KlaviyoState
    
    typealias Action = KlaviyoAction
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let test = Store(initialState: .test, reducer: KlaviyoTestReducer())
}

extension FileClient {
    static let test = FileClient(
        write: { _,_ in },
        fileExists: { _ in return true },
        removeItem: { _ in },
        libraryDirectory: { TEST_URL }
    )
}

extension KlaviyoAPI {
    static let test = { KlaviyoAPI(send: { _ in return .success(TEST_RETURN_DATA) }) }
}

extension LoggerClient {
    static var lastLoggedMessage: String?
    static let test = LoggerClient { message in
        lastLoggedMessage = message
    }
}

extension NetworkSession {
    static let successfulRepsonse = HTTPURLResponse(url: TEST_URL, statusCode: 200, httpVersion: nil, headerFields: nil)!
    static let DEFAULT_CALLBACK: (URLRequest) async throws -> (Data, URLResponse) = { request in
        return (Data(), successfulRepsonse)
    }
    static func test(data: @escaping (URLRequest) async throws -> (Data, URLResponse) = DEFAULT_CALLBACK) -> NetworkSession {
       return NetworkSession(data: data)
    }
}

extension AppContextInfo {
    static let test = Self.init(excutable: "FooApp",
                                bundleId: "com.klaviyo.fooapp",
                                appVersion: "1.2.3",
                                appBuild: "1",
                                version: OperatingSystemVersion(majorVersion: 1, minorVersion: 1, patchVersion: 1),
                                osName: "kOS"
    )
}

extension StateChangePublisher {
    static let test = { () -> StateChangePublisher in
        StateChangePublisher.debouncedPublisher = { publisher in
            publisher
                .debounce(for: .seconds(0), scheduler: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
        return Self.init()
    }()
}

