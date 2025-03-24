//
//  KlaviyoTestUtils.swift
//  KlaviyoSwiftTests
//
//  Created by Noah Durell on 9/30/22.
//
import Combine
import CombineSchedulers
import KlaviyoCore
import KlaviyoSDKDependencies
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

let ARCHIVED_RETURNED_DATA = Data()

@MainActor
extension ArchiverClient {
    static let test = ArchiverClient(
        archivedData: { _, _ in ARCHIVED_RETURNED_DATA },
        unarchivedMutableArray: { _ in SAMPLE_DATA }
    )
}

@MainActor
extension AppLifeCycleEvents {
    static let test = Self(lifeCycleEvents: { _, _, _, _ in Empty<LifeCycleEvents, Never>().eraseToAnyPublisher() })
}

@MainActor
extension KlaviyoEnvironment {
    static var lastLog: String?
    @MainActor static var test = {
        KlaviyoEnvironment(
            archiverClient: ArchiverClient.test,
            fileClient: FileClient.test,
            dataFromUrl: { _ in TEST_RETURN_DATA },
            logger: LoggerClient.test,
            notificationCenterPublisher: { _ in Empty<Notification, Never>().eraseToAnyPublisher() },
            getNotificationSettings: { .authorized },
            getBadgeAutoClearingSetting: { true },
            startReachability: {},
            stopReachability: {},
            reachabilityStatus: { nil },
            randomInt: { 0 },
            raiseFatalError: { _ in },
            emitDeveloperWarning: { _ in },
            apiURL: { URLComponents(string: "https://dead_beef")! },
            cdnURL: { URLComponents(string: "https://dead_beef")! },
            encodeJSON: { _ in TEST_RETURN_DATA },
            decoder: DataDecoder(jsonDecoder: TestJSONDecoder()),
            uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
            date: { Date(timeIntervalSince1970: 1_234_567_890) },
            timeZone: { "EST" },
            klaviyoAPI: KlaviyoAPI.test(),
            timer: { _ in AsyncStream { continuation in
                continuation.yield(Date())
                continuation.finish()
            } },
            appContextInfo: { AppContextInfo.test })
    }
}

class TestJSONDecoder: JSONDecoder, @unchecked Sendable {
    override func decode<T>(_: T.Type, from _: Data) throws -> T where T: Decodable {
        KlaviyoState.test as! T
    }
}

class InvalidJSONDecoder: JSONDecoder, @unchecked Sendable {
    override func decode<T>(_: T.Type, from _: Data) throws -> T where T: Decodable {
        throw KlaviyoDecodingError.invalidType
    }
}

struct KlaviyoTestReducer: Reducer {
    func reduce(into state: inout KlaviyoSwift.KlaviyoState, action: KlaviyoSwift.KlaviyoAction) -> KlaviyoSDKDependencies.Effect<KlaviyoSwift.KlaviyoAction> {
        reducer(&state, action)
    }

    var reducer: (inout KlaviyoSwift.KlaviyoState, KlaviyoAction) -> Effect<KlaviyoAction> = { _, _ in .none }

    typealias State = KlaviyoState

    typealias Action = KlaviyoAction
}

extension Store where State == KlaviyoState, Action == KlaviyoAction {
    static let test = Store(initialState: .test) {
        KlaviyoTestReducer()
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
    @MainActor static let test = { KlaviyoAPI(send: { _, _, _ in .success(TEST_RETURN_DATA) }) }
}

extension LoggerClient {
    @MainActor static var lastLoggedMessage: String?
    @MainActor static let test = LoggerClient { message in
        lastLoggedMessage = message
    }
}

@MainActor
extension NetworkSession {
    static let successfulRepsonse = HTTPURLResponse(url: TEST_URL, statusCode: 200, httpVersion: nil, headerFields: nil)!
    static let DEFAULT_CALLBACK: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { _ in
        (Data(), successfulRepsonse)
    }

    static func test(data: @Sendable @escaping (URLRequest) async throws -> (Data, URLResponse) = DEFAULT_CALLBACK) -> NetworkSession {
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
                           deviceId: "fe-fi-fo-fum",
                           environment: "debug",
                           klaviyoSdk: "swift",
                           sdkVersion: "4.3.0")
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
        actionIdentifier: String = UNNotificationDefaultActionIdentifier
    ) throws -> UNNotificationResponse {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        let request = UNNotificationRequest(
            identifier: "",
            content: content,
            trigger: nil
        )

        let notification = try XCTUnwrap(UNNotification(coder: KeyedArchiver(requiringSecureCoding: false)))
        notification.setValue(request, forKey: "request")

        let response = try XCTUnwrap(UNNotificationResponse(coder: KeyedArchiver(requiringSecureCoding: false)))
        response.setValue(notification, forKey: "notification")
        response.setValue(actionIdentifier, forKey: "actionIdentifier")
        return response
    }
}

// Simplistic equality for testing.
extension KlaviyoAPIError: Equatable {
    public static func ==(lhs: KlaviyoCore.KlaviyoAPIError, rhs: KlaviyoCore.KlaviyoAPIError) -> Bool {
        switch (lhs, rhs) {
        case let (.dataEncodingError(lhsReq), .dataEncodingError(rhsReq)):
            return lhsReq == rhsReq
        case let (.httpError(lhsCode, _), .httpError(rhsCode, _)):
            return lhsCode == rhsCode
        case let (.rateLimitError(backOff: lhsBackOff), .rateLimitError(backOff: rhsBackoff)):
            return lhsBackOff == rhsBackoff
        case (.missingOrInvalidResponse, .missingOrInvalidResponse):
            return true
        case (.networkError, .networkError):
            return true
        case (.internalError, .internalError):
            return true
        case (.internalRequestError, .internalRequestError):
            return true
        case (.unknownError, .unknownError):
            return true
        case (.invalidData, .invalidData):
            return true
        default:
            return false
        }
    }
}

extension TestStore where Action == KlaviyoAction, State == KlaviyoState {
    static let testStore = { initialState in TestStore(initialState: initialState) {
        KlaviyoReducer()
    }
    }
}
