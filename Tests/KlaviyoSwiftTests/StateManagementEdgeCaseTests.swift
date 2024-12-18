//
//  StateManagementEdgeCaseTests.swift
//  Move some state management that feel edge casey over here. These are less likely to happen but still want to cover the code.
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

@MainActor
class StateManagementEdgeCaseTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    // MARK: - initialization

    func testInitializeWhileInitializing() async throws {
        let initialState = KlaviyoState(queue: [], requestsInFlight: [])
        let store = TestStore.testStore(initialState)
        store.exhaustivity = .off

        environment.fileClient.fileExists = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return true
        }

        let apiKey = "fake-key"

        // Avoids a warning in xcode despite the result being discardable.
        _ = await store.send(.initialize(apiKey, .test)) {
            $0.apiKey = apiKey
            $0.initalizationState = .initializing
        }

        // Should be no state change here.
        _ = await store.send(.initialize(apiKey, .test))
    }

    func testInitializeAfterInitialized() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore.testStore(initialState)

        // Using the same key shouldn't do much
        _ = await store.send(KlaviyoAction.initialize(initialState.apiKey!, AppContextInfo.test))

        let newApiKey = "new-api-key"
        // Using a new key should update the key and generate two requests
        _ = await store.send(.initialize(newApiKey, .test)) {
            $0.queue = [$0.buildUnregisterRequest(apiKey: $0.apiKey!, anonymousId: $0.anonymousId!, pushToken: $0.pushTokenData!.pushToken),
                        $0.buildTokenRequest(apiKey: newApiKey, anonymousId: $0.anonymousId!, pushToken: $0.pushTokenData!.pushToken, enablement: $0.pushTokenData!.pushEnablement, background: $0.pushTokenData!.pushBackground, appContextInfo: .test)]
            $0.apiKey = newApiKey
        }
    }

    // MARK: - Send Request

    func testSendRequestBeforeInitialization() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: true)
        let store = TestStore.testStore(initialState)
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
                                                         flushing: true)) {
            KlaviyoReducer()
        }
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
                                                         flushing: true)) {
            KlaviyoReducer()
        }
        // Attempting to get more coverage
        _ = await store.send(.completeInitialization(initialState)) {
            $0.initalizationState = .initialized
            $0.anonymousId = "foo"
        }
        await store.receive(.start)
        await store.receive(.setPushEnablement(PushEnablement.authorized, .available, .test))
        await store.receive(.setBadgeCount(0))
        await store.receive(.flushQueue(.test))
    }

    // MARK: - Set Email

    func testSetEmailUninitializedDoesNotAddToPendingRequest() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.logger.error = { _ in
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
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setEmail("test@blob.com", .test))

        await fulfillment(of: [expection])
    }

    func testSetEmailMissingAnonymousIdStillSetsEmail() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setEmail("test@blob.com", .test)) {
            $0.email = "test@blob.com"
        }
    }

    func testSetEmptyEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setEmail("", .test))
    }

    func testSetEmailWithWhiteSpace() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setEmail("        ", .test))
    }

    // MARK: - Set External Id

    func testSetExternalIdUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setExternalId("external-blob-id", .test))
    }

    func testSetExternalIdMissingAnonymousIdStillSetsExternalId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setExternalId("external-blob-id", .test)) {
            $0.externalId = "external-blob-id"
        }
    }

    func testSetEmptyExternalId() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setExternalId("", .test))
    }

    func testSetExternalIdWithWhiteSpaces() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setExternalId("", .test))
    }

    // MARK: - Set Phone number

    func testSetPhoneNumberUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u", .test))
    }

    func testSetPhoneNumberMissingApiKeyStillSetsPhoneNumber() async throws {
        let initialState = KlaviyoState(anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setPhoneNumber("1-800-Blobs4u", .test)) {
            $0.phoneNumber = "1-800-Blobs4u"
        }
    }

    func testSetEmptyPhoneNumber() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setPhoneNumber("", .test))
    }

    func testSetPhoneNumberWithWhiteSpaces() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setPhoneNumber("", .test))
    }

    // MARK: - Set Push Token

    func testSetPushTokenUninitializedDoesNotAddToPendingRequest() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.setPushToken("blob_token", .authorized, .available, .test))
    }

    func testSetPushTokenWithMissingAnonymousId() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        // Impossible case really but we want coverage
        _ = await store.send(.setPushToken("blob_token", .authorized, .available, .test)) {
            $0.pendingRequests = [.pushToken("blob_token", .authorized, .available, .test)]
        }
    }

    // MARK: - Stop

    func testStopUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.stop)
    }

    func testStopInitializing() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initializing,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.stop)
    }

    // MARK: - Start

    func testStartUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.start)
    }

    // MARK: - Default Badge Clearing

    @MainActor
    func testDefaultBadgeClearingOn() async throws {
        let apiKey = "fake-key"
        environment.getBadgeAutoClearingSetting = { true }
        let expectation = XCTestExpectation(description: "Should set badge to 0")
        klaviyoSwiftEnvironment.setBadgeCount = { _ in
            expectation.fulfill()
        }
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: "foo", queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
                                                         initalizationState: .initializing,
                                                         flushing: true)) { KlaviyoReducer() }
        // Attempting to get more coverage
        _ = await store.send(.completeInitialization(initialState)) {
            $0.initalizationState = .initialized
            $0.anonymousId = "foo"
        }
        await store.receive(.start)

        await store.receive(.setPushEnablement(PushEnablement.authorized, .available, .test))
        await store.receive(.setBadgeCount(0))
        await store.receive(.flushQueue(.test))
        await fulfillment(of: [expectation], timeout: 1, enforceOrder: true)
    }

    // MARK: - Default Badge Clearing Turned Off

    @MainActor
    func testDefaultBadgeClearingOff() async {
        let apiKey = "fake-key"
        environment.getBadgeAutoClearingSetting = { false }
        let expectation = XCTestExpectation(description: "Should not set badge to 0")
        expectation.isInverted = true
        klaviyoSwiftEnvironment.setBadgeCount = { _ in
            expectation.fulfill()
        }
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: "foo", queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: KlaviyoState(apiKey: apiKey,
                                                         email: "foo@foo.com", phoneNumber: "1800-blobs4u", externalId: "external-id", queue: [],
                                                         requestsInFlight: [],
                                                         initalizationState: .initializing,
                                                         flushing: true)) { KlaviyoReducer() }
        // Attempting to get more coverage
        _ = await store.send(.completeInitialization(initialState)) {
            $0.initalizationState = .initialized
            $0.anonymousId = "foo"
        }
        await store.receive(.start)
        await store.receive(.setPushEnablement(PushEnablement.authorized, PushBackground.available, .test))
        await store.receive(.flushQueue(.test))
        await fulfillment(of: [expectation], timeout: 1, enforceOrder: true)
    }

    // MARK: - Network Status Changed

    func testNetworkStatusChangedUninitialized() async {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        anonymousId: environment.uuid().uuidString,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore.testStore(initialState)

        _ = await store.send(.networkConnectivityChanged(.reachableViaWWAN))
    }

    // MARK: - Missing api key for token request

    func testTokenRequestMissingApiKey() async {
        let initialState = KlaviyoState(
            anonymousId: environment.uuid().uuidString,
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: false)
        let store = TestStore.testStore(initialState)

        // Impossible case really but we want coverage on it.
        _ = await store.send(.setPushToken("blobtoken", .authorized, .available, .test)) {
            $0.pendingRequests = [.pushToken("blobtoken", .authorized, .available, .test)]
        }
    }

    // MARK: - set enqueue event uninitialized

    func testOpenedPushEventUninitializedAddsToPendingRequests() async throws {
        let store = TestStore(initialState: .init(queue: [])) {
            KlaviyoReducer()
        }
        let event = Event(name: ._openedPush)
        _ = await store.send(.enqueueEvent(event, .test)) {
            $0.pendingRequests = [.event(event, .test)]
        }
    }

    func testEnqueueNonOpenedPushEventUninitializedDoesNotAddToPendingRequest() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.logger.error = { _ in
            // Would really runTimeWarn - not happening because we can't do that in tests so we fake it.
            expection.fulfill()
        }
        let store = TestStore(initialState: .init(queue: [])) {
            KlaviyoReducer()
        }

        let nonOpenedPushEvents = Event.EventName.allCases.filter { $0 != ._openedPush }

        for event in nonOpenedPushEvents {
            let event = Event(name: event)
            _ = await store.send(.enqueueEvent(event, .test))
        }

        await fulfillment(of: [expection])
    }

    // MARK: - set profile uninitialized

    func testSetProfileUnitialized() async throws {
        let expection = XCTestExpectation(description: "fatal error expected")
        environment.logger.error = { _ in
            expection.fulfill()
        }
        let store = TestStore(initialState: .init(queue: [])) {
            KlaviyoReducer()
        }
        let profile = Profile(email: "foo")
        _ = await store.send(.enqueueProfile(profile, .test))
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
                                 deviceData: .init(context: .test)),
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized,
            flushing: true)

        let store = TestStore.testStore(initialState)

        _ = await store.send(.enqueueProfile(Profile(email: "", phoneNumber: "", externalId: ""), .test)) {
            $0.email = nil // since we reset state
            $0.phoneNumber = nil // since we reset state
            $0.externalId = nil // since we reset state
            $0.enqueueProfileOrTokenRequest(appConextInfo: .test)
            $0.pushTokenData = nil
        }
    }
}

extension Event.EventName: CaseIterable {
    public static var allCases: [KlaviyoSwift.Event.EventName] {
        [._openedPush, .openedAppMetric, .viewedProductMetric, .addedToCartMetric, .startedCheckoutMetric, .customEvent("someEvent")]
    }
}
