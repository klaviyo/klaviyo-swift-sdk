//
//  KlaviyoTestUtils.swift
//  KlaviyoSwiftTests
//
//  Created by Noah Durell on 9/30/22.
//

@testable import KlaviyoCore
import Combine
import CoreLocation
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

/// Resets the canonical KlaviyoCore stores to a clean, deterministic state for test isolation.
///
/// `IdentityStore.shared` and `SDKConfigStore.shared` are process-wide singletons that persist
/// across tests. Call this
/// in `setUp` — AFTER installing the test `environment` — so hydration/minting use the test
/// `fileClient` (whose `fileExists` closure decides whether `loadPersisted` reads or returns nil)
/// and the deterministic test `uuid`, and so state never leaks between tests.
func resetCanonicalCoreStores() {
    IdentityStore.shared.reset()
    SDKConfigStore.shared.reset()
    // The shared QueueStore is process-global; clear it so a spy store injected by
    // `seedTestQueueStore` in one test can't bleed into the next (which would otherwise resolve a
    // stale in-memory queue instead of the empty production/disk-backed store).
    QueueStore.resetShared()
}

/// Bounded async poll: waits until `condition` holds or `timeout` elapses. FAILS (XCTFail) on
/// timeout rather than spinning forever, so a broken async path surfaces loudly.
func waitForConditionOrFail(
    timeout: TimeInterval = 2.0,
    _ message: @autoclosure () -> String = "condition not met within timeout",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail(message(), file: file, line: line)
}

/// Shared base for KlaviyoSwift test suites. Resets the same process-wide singletons
/// (test `environment`, canonical Core stores, the durable buffer, and `BadgeManager`) before each
/// test. Subclasses that need extra setup should call `super` first.
class KlaviyoBaseTestCase: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        featureFlags = .production
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        ProfilePropertyBuffer.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        BadgeManager.resetToProduction()
    }

    @MainActor
    override func tearDown() async throws {
        ProfilePropertyBuffer.shared.reset()
        BadgeManager.resetToProduction()
    }

    /// Installs a `SpyRequestQueue` as the environment request queue and returns it. The spy records
    /// lifecycle/flush calls without draining `QueueStore`, so queue-content assertions stay
    /// deterministic (and the real run loop never spins under the immediate test clock).
    @discardableResult
    func installSpyRequestQueue() -> SpyRequestQueue {
        let spyQueue = SpyRequestQueue()
        klaviyoSwiftEnvironment.requestQueue = spyQueue
        return spyQueue
    }

    /// Seeds a post-init state: apiKey in `SDKConfigStore`, identity + push token in `IdentityStore`,
    /// `LifecycleState` advanced to `.initialized`. Returns (apiKey, anonymousId, pushToken).
    @discardableResult
    func seedPostInitWithToken(
        apiKey: String = TEST_API_KEY,
        anonymousId: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        pushToken: String = "blob_token"
    ) -> (apiKey: String, anonymousId: String, pushToken: String) {
        let resolvedAnon = anonymousId ?? environment.uuid().uuidString
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(ProfileData(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: resolvedAnon
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushToken,
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()
        return (apiKey, resolvedAnon, pushToken)
    }

    /// Seeds a pre-init state: anonymousId only in `IdentityStore`, `LifecycleState` stays
    /// `.uninitialized`.
    func seedPreInit(anonymousId: String? = nil) {
        let resolvedAnon = anonymousId ?? environment.uuid().uuidString
        IdentityStore.shared.update(ProfileData(anonymousId: resolvedAnon))
    }
}

extension AppLifeCycleEvents {
    static let test = Self(lifeCycleEvents: { Empty<LifeCycleEvents, Never>().eraseToAnyPublisher() })
}

extension KlaviyoEnvironment {
    static var lastLog: String?
    static var test = {
        KlaviyoEnvironment(
            fileClient: FileClient.test,
            dataFromUrl: { _ in TEST_RETURN_DATA },
            logger: LoggerClient.test,
            appLifeCycle: AppLifeCycleEvents.test,
            notificationCenterPublisher: { _ in Empty<Notification, Never>().eraseToAnyPublisher() },
            getNotificationSettings: { .authorized },
            getBackgroundSetting: { .available },
            getBadgeAutoClearingSetting: { true },
            getLocationAuthorizationStatus: { .authorizedAlways },
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
            SDKName: { __klaviyoSwiftName },
            SDKVersion: { __klaviyoSwiftVersion },
            formsDataEnvironment: { nil },
            linkHandler: DeepLinkHandler()
        )
    }
}

class TestJSONDecoder: JSONDecoder, @unchecked Sendable {}

class InvalidJSONDecoder: JSONDecoder, @unchecked Sendable {
    private struct DecodingFailure: Error {}
    override func decode<T>(_: T.Type, from _: Data) throws -> T where T: Decodable {
        throw DecodingFailure()
    }
}

extension FileClient {
    static let test = FileClient(
        write: { _, _ in },
        fileExists: { _ in true },
        removeItem: { _ in },
        libraryDirectory: { TEST_URL },
        applicationSupportDirectory: { TEST_URL }
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
