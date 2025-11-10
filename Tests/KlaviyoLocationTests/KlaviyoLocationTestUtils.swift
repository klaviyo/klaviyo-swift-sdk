//
//  KlaviyoLocationTestUtils.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

@testable import KlaviyoCore
import Combine
import CoreLocation
import Foundation
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

// MARK: - Test Constants

private let TEST_RETURN_DATA = "test data".data(using: .utf8)!
private let TEST_URL = URL(string: "file:///test")!

// MARK: - Test Environment Extensions

extension KlaviyoEnvironment {
    static var test = {
        KlaviyoEnvironment(
            archiverClient: ArchiverClient.production,
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
            networkSession: { NetworkSession.production },
            apiURL: { URLComponents(string: "https://test.klaviyo.com")! },
            cdnURL: { URLComponents(string: "https://test.klaviyo.com")! },
            encodeJSON: { _ in TEST_RETURN_DATA },
            decoder: DataDecoder.production,
            uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
            date: { Date(timeIntervalSince1970: 1_234_567_890) },
            timeZone: { "EST" },
            appContextInfo: { AppContextInfo.test },
            klaviyoAPI: KlaviyoAPI.test(),
            timer: { _ in Just(Date()).eraseToAnyPublisher() },
            SDKName: { "klaviyo-swift-sdk" },
            SDKVersion: { "1.0.0" },
            formsDataEnvironment: { nil },
            linkHandler: DeepLinkHandler()
        )
    }
}

// MARK: - Test Client Extensions

extension FileClient {
    static let test = FileClient(
        write: { _, _ in },
        fileExists: { _ in true },
        removeItem: { _ in },
        libraryDirectory: { TEST_URL }
    )
}

extension LoggerClient {
    static let test = LoggerClient(
        error: { _ in }
    )
}

extension AppLifeCycleEvents {
    static let test = AppLifeCycleEvents(
        lifeCycleEvents: { Empty<LifeCycleEvents, Never>().eraseToAnyPublisher() }
    )
}

extension AppContextInfo {
    static let test = AppContextInfo(
        executable: "test",
        bundleId: "com.klaviyo.test",
        appVersion: "1.0.0",
        appBuild: "1",
        appName: "TestApp",
        version: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0),
        osName: "iOS",
        manufacturer: "Apple",
        deviceModel: "iPhone",
        deviceId: "test-device-id"
    )
}

extension KlaviyoAPI {
    static let test = { KlaviyoAPI(send: { _, _ in .success(TEST_RETURN_DATA) }) }
}

extension KlaviyoState {
    static let test = KlaviyoState(
        apiKey: "ABC123",
        email: "test@test.com",
        anonymousId: "test-anonymous-id",
        phoneNumber: "1234567890",
        externalId: "test-external-id",
        pushTokenData: nil,
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized,
        flushing: false,
        flushInterval: 30.0,
        retryState: .retry(1),
        pendingRequests: [],
        pendingProfile: nil
    )
}

// MARK: - Test Data Helpers

enum KlaviyoLocationTestUtils {
    /// Creates test geofence data in the JSON API format
    static func createTestGeofenceData() -> Data {
        let jsonString = """
        {
            "data": [
                {
                    "type": "geofence",
                    "id": "8db4effa-44f1-45e6-a88d-8e7d50516a0f",
                    "attributes": {
                        "latitude": 40.7128,
                        "longitude": -74.006,
                        "radius": 100
                    }
                },
                {
                    "type": "geofence",
                    "id": "a84011cf-93ef-4e78-b047-c0ce4ea258e4",
                    "attributes": {
                        "latitude": 40.6892,
                        "longitude": -74.0445,
                        "radius": 200
                    }
                }
            ]
        }
        """
        return jsonString.data(using: .utf8)!
    }

    /// Creates a test KlaviyoState with a specific API key
    static func createTestState(apiKey: String) -> KlaviyoState {
        var testState = KlaviyoState.test
        testState.apiKey = apiKey
        return testState
    }

    /// Sets up the test environment with a mocked API key
    static func setupTestEnvironment(apiKey: String) {
        environment = KlaviyoEnvironment.test()
        KlaviyoInternal.resetAPIKeySubject()

        let testState = createTestState(apiKey: apiKey)
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }
    }
}
