//
//  StateManagementTests.swift
//
//
//  Created by Noah Durell on 12/6/22.
//

@testable import KlaviyoSwift
import AnyCodable
import Combine
import Foundation
import KlaviyoCore
import XCTest

class StateManagementTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    // MARK: - Initialization

    @MainActor
    func testInitialize() async throws {
        let initialState = KlaviyoState(queue: [], requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let apiKey = "fake-key"
        // Avoids a warning in xcode despite the result being discardable.
        await store.send(.initialize(apiKey)) {
            $0.apiKey = apiKey
            $0.initalizationState = .initializing
        }

        let expectedState = KlaviyoState(apiKey: apiKey, anonymousId: environment.uuid().uuidString, queue: [], requestsInFlight: [])
        await store.receive(.completeInitialization(expectedState)) {
            $0.anonymousId = expectedState.anonymousId
            $0.initalizationState = .initialized
            $0.queue = []
        }

        await store.receive(.start)
        await store.receive(.flushQueue)
        await store.receive(.setPushEnablement(PushEnablement.authorized))
    }

    @MainActor
    func testInitializeSubscribesToAppropriatePublishers() async throws {
        let lifecycleExpectation = XCTestExpectation(description: "lifecycle is subscribed")
        let stateChangeIsSubscribed = XCTestExpectation(description: "state change is subscribed")
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        environment.appLifeCycle.lifeCycleEvents = {
            lifecycleSubject.handleEvents(receiveSubscription: { _ in
                lifecycleExpectation.fulfill()
            })
            .eraseToAnyPublisher()
        }
        let stateChangeSubject = PassthroughSubject<KlaviyoAction, Never>()
        klaviyoSwiftEnvironment.stateChangePublisher = {
            stateChangeSubject.handleEvents(receiveSubscription: { _ in
                stateChangeIsSubscribed.fulfill()
            })
            .eraseToAnyPublisher()
        }
        let initialState = KlaviyoState(queue: [], requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let apiKey = "fake-key"
        _ = await store.send(.initialize(apiKey))

        stateChangeSubject.send(completion: .finished)
        lifecycleSubject.send(completion: .finished)

        await fulfillment(of: [stateChangeIsSubscribed, lifecycleExpectation])
    }

    // MARK: - Set Email

    @MainActor
    func testSetEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("test@blob.com")) {
            $0.email = "test@blob.com"
            let request = $0.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: $0.pushTokenData!.pushToken, enablement: $0.pushTokenData!.pushEnablement)
            $0.queue = [request]
            $0.pushTokenData = nil
        }
    }

    // MARK: Set Phone Number

    @MainActor
    func testSetPhoneNumber() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("+1800555BLOB")) {
            $0.phoneNumber = "+1800555BLOB"
            let request = $0.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: $0.pushTokenData!.pushToken, enablement: $0.pushTokenData!.pushEnablement)
            $0.queue = [request]
            $0.pushTokenData = nil
        }
    }

    // MARK: - Set External Id.

    @MainActor
    func testSetExternalId() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("external-blob")) {
            $0.externalId = "external-blob"
            let request = $0.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: $0.pushTokenData!.pushToken, enablement: $0.pushTokenData!.pushEnablement)
            $0.queue = [request]
            $0.pushTokenData = nil
        }
    }

    // MARK: - Set Push Token

    @MainActor
    func testSetPushToken() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let pushTokenRequest = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blobtoken", enablement: .authorized)
        _ = await store.send(.setPushToken("blobtoken", .authorized)) {
            $0.queue = [pushTokenRequest]
        }

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
        }

        await store.receive(.sendRequest)

        _ = await store.receive(.deQueueCompletedResults(pushTokenRequest)) {
            $0.flushing = false
            $0.requestsInFlight = []
            $0.pushTokenData = KlaviyoState.PushTokenData(pushToken: "blobtoken", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.appContextInfo()))
        }
    }

    @MainActor
    func testSetPushTokenEnablementChanged() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData?.pushEnablement = .denied
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let pushTokenRequest = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: .authorized)

        _ = await store.send(.setPushToken(initialState.pushTokenData!.pushToken, .authorized)) {
            $0.queue = [pushTokenRequest]
        }

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
        }

        await store.receive(.sendRequest)

        _ = await store.receive(.deQueueCompletedResults(pushTokenRequest)) {
            $0.flushing = false
            $0.requestsInFlight = []
            $0.pushTokenData = KlaviyoState.PushTokenData(
                pushToken: initialState.pushTokenData!.pushToken,
                pushEnablement: .authorized,
                pushBackground: initialState.pushTokenData!.pushBackground,
                deviceData: initialState.pushTokenData!.deviceData)
        }
    }

    @MainActor
    func testSetPushTokenMultipleTimes() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let pushTokenRequest = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blobtoken", enablement: .authorized)

        _ = await store.send(.setPushToken("blobtoken", .authorized)) {
            $0.queue = [pushTokenRequest]
        }

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
        }

        await store.receive(.sendRequest)

        _ = await store.receive(.deQueueCompletedResults(pushTokenRequest)) {
            $0.flushing = false
            $0.requestsInFlight = []
            $0.pushTokenData = KlaviyoState.PushTokenData(pushToken: "blobtoken", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.appContextInfo()))
        }
        _ = await store.send(.setPushToken("blobtoken", .authorized))
    }

    // MARK: - Set Push Enablement

    @MainActor
    func testSetPushEnablementPushTokenIsNil() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData = nil
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.setPushEnablement(.authorized))
    }

    @MainActor
    func testSetPushEnablementChanged() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.pushTokenData?.pushEnablement = .denied
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let pushTokenRequest = initialState.buildTokenRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!,
            pushToken: initialState.pushTokenData!.pushToken,
            enablement: .authorized)

        _ = await store.send(.setPushEnablement(.authorized))

        await store.receive(.setPushToken(initialState.pushTokenData!.pushToken, .authorized)) {
            $0.queue = [pushTokenRequest]
        }
    }

    // MARK: - flush

    @MainActor
    func testFlushUninitializedQueueDoesNotFlush() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .uninitialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.flushQueue)
    }

    @MainActor
    func testQueueThatIsFlushingDoesNotFlush() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: true)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.flushQueue)
    }

    @MainActor
    func testEmptyQueueDoesNotFlush() async throws {
        let apiKey = "fake-key"
        let initialState = KlaviyoState(apiKey: apiKey,
                                        queue: [],
                                        requestsInFlight: [],
                                        initalizationState: .initialized,
                                        flushing: false)
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.flushQueue)
    }

    @MainActor
    func testFlushQueueWithMultipleRequests() async throws {
        var count = 0
        // request uuids need to be unique :)
        environment.uuid = {
            count += 1
            switch count {
            case 1:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            case 2:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            default:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            }
        }
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        initialState.queue = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
        }
        await store.receive(.sendRequest)

        await store.receive(.deQueueCompletedResults(request)) {
            $0.flushing = true
            $0.requestsInFlight = [request2]
            $0.queue = []
        }
        await store.receive(.sendRequest)
        await store.receive(.deQueueCompletedResults(request2)) {
            $0.pushTokenData = KlaviyoState.PushTokenData(pushToken: "blob_token", pushEnablement: .authorized, pushBackground: .available, deviceData: .init(context: environment.appContextInfo()))
            $0.flushing = false
            $0.requestsInFlight = []
            $0.queue = []
        }
    }

    @MainActor
    func testFlushQueueDuringExponentialBackoff() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200)
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        initialState.queue = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.retryInfo = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200 - Int(initialState.flushInterval))
        }
    }

    @MainActor
    func testFlushQueueExponentialBackoffGoesToSize() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: Int(initialState.flushInterval) - 2)
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        initialState.queue = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.retryInfo = .retry(23)
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
        }
        await store.receive(.sendRequest)

        // didn't fake uuid since we are not testing this.
        await store.receive(.deQueueCompletedResults(request)) {
            $0.flushing = false
            $0.retryInfo = .retry(1)
            $0.requestsInFlight = []
            $0.queue = []
        }
    }

    @MainActor
    func testSendRequestWhenNotFlushing() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest)
    }

    // MARK: - send request

    @MainActor
    func testSendRequestWithNoRequestsInFlight() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest) {
            $0.flushing = false
        }
    }

    // MARK: - Network Connectivity Changed

    @MainActor
    func testNetworkConnectivityChanges() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.networkConnectivityChanged(.notReachable)) {
            $0.flushInterval = Double.infinity
        }
        _ = await store.receive(.cancelInFlightRequests) {
            $0.flushing = false
        }
        _ = await store.send(.networkConnectivityChanged(.reachableViaWiFi)) {
            $0.flushing = false
            $0.flushInterval = StateManagementConstants.wifiFlushInterval
        }
        await store.receive(.flushQueue)
        _ = await store.send(.networkConnectivityChanged(.reachableViaWWAN)) {
            $0.flushInterval = StateManagementConstants.cellularFlushInterval
        }
        await store.receive(.flushQueue)
    }

    // MARK: - Stop

    @MainActor
    func testStopWithRequestsInFlight() async throws {
        // This test is a little convoluted but essentially want to make when we stop
        // that we save our state.
        var initialState = INITIALIZED_TEST_STATE()
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        initialState.requestsInFlight = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.stop)

        await store.receive(.cancelInFlightRequests) {
            $0.flushing = false
            $0.queue = [request, request2]
            $0.requestsInFlight = []
        }
    }

    // MARK: - Test pending profile

    @MainActor
    func testFlushWithPendingProfile() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let profileAttributes: [(Profile.ProfileKey, Any)] = [
            (.city, Profile.test.location!.city!),
            (.region, Profile.test.location!.region!),
            (.address1, Profile.test.location!.address1!),
            (.address2, Profile.test.location!.address2!),
            (.zip, Profile.test.location!.zip!),
            (.country, Profile.test.location!.country!),
            (.latitude, Profile.test.location!.latitude!),
            (.longitude, Profile.test.location!.longitude!),
            (.title, Profile.test.title!),
            (.organization, Profile.test.organization!),
            (.firstName, Profile.test.firstName!),
            (.lastName, Profile.test.lastName!),
            (.image, Profile.test.image!),
            (.custom(customKey: "foo"), 20)
        ]

        var pendingProfile = [Profile.ProfileKey: AnyEncodable]()

        for (key, value) in profileAttributes {
            pendingProfile[key] = AnyEncodable(value)
            _ = await store.send(.setProfileProperty(key, AnyEncodable(value))) {
                $0.pendingProfile = pendingProfile
            }
        }

        var request: KlaviyoRequest?

        _ = await store.send(.flushQueue) {
            $0.enqueueProfileOrTokenRequest()
            $0.requestsInFlight = $0.queue
            $0.queue = []
            $0.flushing = true
            $0.pendingProfile = nil
            request = $0.requestsInFlight[0]
            switch request?.endpoint {
            case let .registerPushToken(payload):
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.city, Profile.test.location!.city)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.region, Profile.test.location!.region!)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.address1, Profile.test.location!.address1!)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.address2, Profile.test.location!.address2!)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.zip, Profile.test.location!.zip!)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.country, Profile.test.location!.country!)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.latitude, Profile.test.location!.latitude!)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.location?.longitude, Profile.test.location!.longitude!)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.title, Profile.test.title)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.organization, Profile.test.organization)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.firstName, Profile.test.firstName)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.lastName, Profile.test.lastName)
                XCTAssertEqual(payload.data.attributes.profile.data.attributes.image, Profile.test.image)

                if let customProperties = payload.data.attributes.profile.data.attributes.properties.value as? [String: Any],
                   let foo = customProperties["foo"] as? Int {
                    XCTAssertEqual(foo, 20)
                }
            default:
                XCTFail("Wrong endpoint called, expected token update when store's initial state contains token data")
            }
        }

        await store.receive(.sendRequest)
        await store.receive(.deQueueCompletedResults(request!)) {
            $0.requestsInFlight = $0.queue
            $0.flushing = false
            $0.pendingProfile = nil
            $0.pushTokenData = initialState.pushTokenData
        }
    }

    // MARK: - Test set profile

    @MainActor
    func testSetProfileWithExistingProperties() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueProfile(Profile(email: "foo"))) {
            $0.phoneNumber = nil
            $0.email = "foo"
            $0.enqueueProfileOrTokenRequest()
            $0.pushTokenData = nil
        }
    }

    @MainActor
    func testSetProfileWithAllProfileIdentifiersAndProperties() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueProfile(Profile.test)) {
            $0.email = Profile.test.email
            $0.phoneNumber = Profile.test.phoneNumber
            $0.externalId = Profile.test.externalId
            $0.pushTokenData = nil

            let request = KlaviyoRequest(
                apiKey: initialState.apiKey!,
                endpoint: .registerPushToken(PushTokenPayload(
                    pushToken: initialState.pushTokenData!.pushToken,
                    enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                    background: initialState.pushTokenData!.pushBackground.rawValue,
                    profile: Profile.test.toAPIModel(anonymousId: initialState.anonymousId!))
                ))
            $0.queue = [request]
        }
    }

    // MARK: - Test enqueue event

    @MainActor
    func testEnqueueEvents() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        for eventName in Event.EventName.allCases {
            let event = Event(name: eventName, properties: ["push_token": initialState.pushTokenData!.pushToken])
            await store.send(.enqueueEvent(event)) {
                try $0.enqueueRequest(
                    request: KlaviyoRequest(
                        apiKey: XCTUnwrap($0.apiKey),
                        endpoint: .createEvent(CreateEventPayload(
                            data: CreateEventPayload.Event(
                                name: eventName.value,
                                properties: event.properties,
                                phoneNumber: $0.phoneNumber,
                                anonymousId: initialState.anonymousId!,
                                time: event.time,
                                pushToken: initialState.pushTokenData!.pushToken)
                        ))))
            }

            // if the event is opened push we want to flush immidietly, for all other events we flush during regular intervals set in code
            if eventName == .OpenedPush {
                await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
            }
        }
    }

    @MainActor
    func testEnqueueEventWhenInitilizingSendsEvent() async throws {
        let initialState = INITILIZING_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let event = Event(name: .OpenedAppMetric)
        await store.send(.enqueueEvent(event)) {
            $0.pendingRequests = [KlaviyoState.PendingRequest.event(event)]
        }

        await store.send(.completeInitialization(initialState)) {
            $0.pendingRequests = []
            $0.initalizationState = .initialized
        }

        await store.receive(.enqueueEvent(event), timeout: TIMEOUT_NANOSECONDS) {
            try $0.enqueueRequest(
                request: KlaviyoRequest(
                    apiKey: XCTUnwrap($0.apiKey),
                    endpoint: .createEvent(CreateEventPayload(
                        data: CreateEventPayload.Event(
                            name: Event.EventName.OpenedAppMetric.value,
                            properties: event.properties,
                            phoneNumber: $0.phoneNumber,
                            anonymousId: initialState.anonymousId!,
                            time: event.time)
                    )))
            )
        }

        await store.receive(.start, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.setPushEnablement(PushEnablement.authorized), timeout: TIMEOUT_NANOSECONDS)
    }
}
