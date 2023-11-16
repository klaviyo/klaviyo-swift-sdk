//
//  StateManagementEdgeCaseTests.swift
//  Move some state management that feel edge casey over here. These are less likely to happen but still want to cover the code.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

@MainActor
class StateManagementEdgeCaseTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    // MARK: - initialization

    func testInitializeWhileInitializing() async throws {
        let initialState = KlaviyoState(queue: [], requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        environment.fileClient.fileExists = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return true
        }

        let apiKey = "fake-key"

        // Avoids a warning in xcode despite the result being discardable.
        _ = await store.send(.initialize(apiKey)) {
            $0.apiKey = apiKey
            $0.initalizationState = .initializing
        }

        // Should be no state change here.
        _ = await store.send(.initialize(apiKey))
    }

    // MARK: - Send Request

    func testSendRequestBeforeInitialization() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: true)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest)
    }

    // MARK: - Complete Initialization

    func testCompleteInitializationWhileAlreadyInitialized() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
                                                         initalizationState: .initialized,
                                                         flushing: true), reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.completeInitialization(initialState))
    }

    func testCompleteInitializationWithExistingIdentifiers() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: "foo", queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
                                                         initalizationState: .initializing,
                                                         flushing: true), reducer: KlaviyoReducer())
        // Attempting to get more coverage
        _ = await store.send(.completeInitialization(initialState)) {
            $0.initalizationState = .initialized
            $0.anonymousId = "foo"
        }
        await store.receive(.start)
        await store.receive(.flushQueue)
    }

    // MARK: - Set Email

    func testSetEmailUninitialized() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("test@blob.com")) {
            $0.pendingRequests.append(.setEmail("test@blob.com"))
        }
    }

    func testSetEmailMissingAnonymousIdStillSetsEmail() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("test@blob.com")) {
            $0.email = "test@blob.com"
        }
    }

    // MARK: - Set External Id

    func testSetExternalIdUninitialized() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("external-blob-id")) {
            $0.pendingRequests.append(.setExternalId("external-blob-id"))
        }
    }

    func testSetExternalIdMissingAnonymousIdStillSetsExternalId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("external-blob-id")) {
            $0.externalId = "external-blob-id"
        }
    }

    // MARK: - Set Phone number

    func testSetPhoneNumberUninitialized() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u")) {
            $0.pendingRequests.append(.setPhoneNumber("1-800-Blobs4u"))
        }
    }

    func testSetPhoneNumberMissingApiKeyStillSetsPhoneNumber() async throws {
        let initialState = KlaviyoState(anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u")) {
            $0.phoneNumber = "1-800-Blobs4u"
        }
    }

    // MARK: - Set Push Token

    func testSetPushTokenUninitialized() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPushToken("blob_token", .authorized)) {
            $0.pendingRequests = [.pushToken("blob_token", .authorized)]
        }
    }

    func testSetPushTokenWithMissingAnonymousId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage
        _ = await store.send(.setPushToken("blob_token", .authorized))
    }

    // MARK: - Stop

    func testStopUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.stop)
    }

    func testStopInitializing() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initializing,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.stop)
    }

    // MARK: - Start

    func testStartUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.start)
    }

    // MARK: - Network Status Changed

    func testNetworkStatusChangedUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.analytics.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.networkConnectivityChanged(.reachableViaWWAN))
    }

    // MARK: - Missing api key for token request

    func testTokenRequestMissingApiKey() async {
        let initialState = KlaviyoState(
            anonymousId: environment.analytics.uuid().uuidString,
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage on it.
        _ = await store.send(.setPushToken("blobtoken", .authorized))
    }

    // MARK: - set enqueue event uninitialized

    func testEnqueueEventUninitialized() async throws {
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())
        let event = Event(name: .OpenedPush, profile: ["$email": "foo", "$phone_number": "666BLOB", "$id": "my_user_id"])
        _ = await store.send(.enqueueEvent(event)) {
            $0.pendingRequests = [.event(event)]
        }
    }

    // MARK: - set profile uninitialized

    func testSetProfileUnitialized() async throws {
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())
        let profile = Profile(email: "foo")
        _ = await store.send(.enqueueProfile(profile)) {
            $0.pendingRequests = [.profile(profile)]
        }
    }
}
