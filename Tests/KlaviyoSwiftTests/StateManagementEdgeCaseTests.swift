//
//  StateManagementEdgeCaseTests.swift
//  Move some state management that feel edge casey over here. These are less likely to happen but still want to cover the code.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

class StateManagementEdgeCaseTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    // MARK: - initialization

    @MainActor
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

    @MainActor
    func testInitializeAfterInitialized() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Using the same key shouldn't do much
        _ = await store.send(.initialize(initialState.apiKey!))

        let newApiKey = "new-api-key"
        // Using a new key should update the key and generate two requests
        _ = await store.send(.initialize(newApiKey)) {
            $0.queue = [$0.buildUnregisterRequest(apiKey: $0.apiKey!, anonymousId: $0.anonymousId!, pushToken: $0.pushTokenData!.pushToken),
                        $0.buildTokenRequest(apiKey: newApiKey, anonymousId: $0.anonymousId!, pushToken: $0.pushTokenData!.pushToken, enablement: $0.pushTokenData!.pushEnablement)]
            $0.apiKey = newApiKey
        }
    }

    // MARK: - Send Request

    @MainActor
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

    @MainActor
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

    @MainActor
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
        await store.receive(.setPushEnablement(PushEnablement.authorized))
    }

    // MARK: - Set Email

    @MainActor
    func testSetEmailUninitializedDoesNotAddToPendingRequest() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.emitDeveloperWarning = { _ in
            // Would really fatalError - not happening because we can't do that in tests so we fake it.
            expection.fulfill()
        }
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("test@blob.com"))

        await fulfillment(of: [expection])
    }

    @MainActor
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

    func testSetEmptyEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail(""))
    }

    func testSetEmailWithWhiteSpace() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("        "))
    }

    // MARK: - Set External Id

    @MainActor
    func testSetExternalIdUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("external-blob-id"))
    }

    @MainActor
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

    func testSetEmptyExternalId() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId(""))
    }

    func testSetExternalIdWithWhiteSpaces() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId(""))
    }

    // MARK: - Set Phone number

    @MainActor
    func testSetPhoneNumberUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u"))
    }

    @MainActor
    func testSetPhoneNumberMissingApiKeyStillSetsPhoneNumber() async throws {
        let initialState = KlaviyoState(anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u")) {
            $0.phoneNumber = "1-800-Blobs4u"
        }
    }

    func testSetEmptyPhoneNumber() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber(""))
    }

    func testSetPhoneNumberWithWhiteSpaces() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber(""))
    }

    // MARK: - Set Push Token

    @MainActor
    func testSetPushTokenUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPushToken("blob_token", .authorized))
    }

    @MainActor
    func testSetPushTokenWithMissingAnonymousId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage
        _ = await store.send(.setPushToken("blob_token", .authorized)) {
            $0.pendingRequests = [.pushToken("blob_token", .authorized)]
        }
    }

    // MARK: - Stop

    @MainActor
    func testStopUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.stop)
    }

    @MainActor
    func testStopInitializing() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initializing,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.stop)
    }

    // MARK: - Start

    @MainActor
    func testStartUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.start)
    }

    // MARK: - Network Status Changed

    @MainActor
    func testNetworkStatusChangedUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.networkConnectivityChanged(.reachableViaWWAN))
    }

    // MARK: - Missing api key for token request

    @MainActor
    func testTokenRequestMissingApiKey() async {
        let initialState = KlaviyoState(
            anonymousId: environment.uuid().uuidString,
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Impossible case really but we want coverage on it.
        _ = await store.send(.setPushToken("blobtoken", .authorized)) {
            $0.pendingRequests = [.pushToken("blobtoken", .authorized)]
        }
    }

    // MARK: - set enqueue event uninitialized

    @MainActor
    func testOpenedPushEventUninitializedAddsToPendingRequests() async throws {
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())
        let event = Event(name: .OpenedPush)
        _ = await store.send(.enqueueEvent(event)) {
            $0.pendingRequests = [.event(event)]
        }
    }

    @MainActor
    func testEnqueueNonOpenedPushEventUninitializedDoesNotAddToPendingRequest() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.emitDeveloperWarning = { _ in
            // Would really runTimeWarn - not happening because we can't do that in tests so we fake it.
            expection.fulfill()
        }
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())

        let nonOpenedPushEvents = Event.EventName.allCases.filter { $0 != .OpenedPush }

        for event in nonOpenedPushEvents {
            let event = Event(name: event)
            _ = await store.send(.enqueueEvent(event))
        }

        await fulfillment(of: [expection])
    }

    // MARK: - set profile uninitialized

    @MainActor
    func testSetProfileUnitialized() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.emitDeveloperWarning = { _ in
            // Would really runTimeWarn - not happening because we can't do that in tests so we fake it.
            expection.fulfill()
        }
        let store = TestStore(initialState: .init(queue: []), reducer: KlaviyoReducer())
        let profile = Profile(email: "foo")
        _ = await store.send(.enqueueProfile(profile))
        await fulfillment(of: [expection])
    }

    func testSetProfileWithEmptyStringIdentifiers() async throws {
        let initialState = KlaviyoState(
            apiKey: TEST_API_KEY,
            email: "foo@bar.com",
            anonymousId: environment.uuid().uuidString,
            phoneNumber: "99999999",
            externalId: "12345",
            pushTokenData: .init(pushToken: "blob_token",
                                 pushEnablement: .authorized,
                                 pushBackground: .available,
                                 deviceData: .init(context: environment.appContextInfo())),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true)

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueProfile(Profile(email: "", phoneNumber: "", externalId: ""))) {
            $0.email = nil // since we reset state
            $0.phoneNumber = nil // since we reset state
            $0.externalId = nil // since we reset state
            $0.enqueueProfileOrTokenRequest()
            $0.pushTokenData = nil
        }
    }
}

extension Event.EventName: CaseIterable {
    public static var allCases: [KlaviyoSwift.Event.EventName] {
        [.OpenedPush, .OpenedAppMetric, .ViewedProductMetric, .AddedToCartMetric, .StartedCheckoutMetric, .CustomEvent("someEvent")]
    }
}
