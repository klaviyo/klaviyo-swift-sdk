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
import XCTest

@MainActor
class StateManagementTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    // MARK: - Initialization

    func testInitialize() async throws {
        let initialState = KlaviyoState(queue: [], requestsInFlight: [])
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let apiKey = "fake-key"
        // Avoids a warning in xcode despite the result being discardable.
        _ = await store.send(.initialize(apiKey)) {
            $0.apiKey = apiKey
            $0.initalizationState = .initializing
        }

        let expectedState = KlaviyoState(apiKey: apiKey, anonymousId: environment.analytics.uuid().uuidString, queue: [], requestsInFlight: [])
        let request = try expectedState.buildProfileRequest()
        await store.receive(.completeInitialization(expectedState)) {
            $0.anonymousId = expectedState.anonymousId
            $0.initalizationState = .initialized
            $0.queue = [request]
        }

        await store.receive(.start)

        await store.receive(.flushQueue) {
            $0.flushing = true
            $0.queue = []
            $0.requestsInFlight = [request]
        }
        await store.receive(.sendRequest)
        await store.receive(.dequeCompletedResults(request)) {
            $0.flushing = false
            $0.requestsInFlight = []
        }
    }

    func testInitializeSubscribesToAppropriatePublishers() async throws {
        let lifecycleExpectation = XCTestExpectation(description: "lifecycle is subscribed")
        let stateChangeIsSubscribed = XCTestExpectation(description: "state change is subscribed")
        let lifecycleSubject = PassthroughSubject<KlaviyoAction, Never>()
        environment.appLifeCycle.lifeCycleEvents = {
            lifecycleSubject.handleEvents(receiveSubscription: { _ in
                lifecycleExpectation.fulfill()
            })
            .eraseToAnyPublisher()
        }
        let stateChangeSubject = PassthroughSubject<KlaviyoAction, Never>()
        environment.stateChangePublisher = {
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

        wait(for: [stateChangeIsSubscribed, lifecycleExpectation], timeout: 1.0)
    }

    // MARK: - Set Email

    func testSetEmail() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setEmail("test@blob.com")) {
            $0.email = "test@blob.com"
            let request = try $0.buildProfileRequest()
            $0.queue = [request]
        }
    }

    // MARK: Set Phone Number

    func testSetPhoneNumber() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPhoneNumber("+1800555BLOB")) {
            $0.phoneNumber = "+1800555BLOB"
            let request = try $0.buildProfileRequest()
            $0.queue = [request]
        }
    }

    // MARK: - Set External Id.

    func testSetExternalId() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setExternalId("external-blob")) {
            $0.externalId = "external-blob"
            let request = try $0.buildProfileRequest()
            $0.queue = [request]
        }
    }

    // MARK: - Set Push Token

    func testSetPushToken() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.setPushToken("blobtoken", .authorized, .available)) {
            $0.pushToken = "blobtoken"
            let request = try $0.buildTokenRequest()
            $0.queue = [request]
        }
    }

    // MARK: - flush

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

    func testFlushQueueWithMultipleRequests() async throws {
        var count = 0
        // request uuids need to be unique :)
        environment.analytics.uuid = {
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
        let request = try initialState.buildProfileRequest()
        let request2 = try initialState.buildTokenRequest()
        initialState.queue = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
        }
        await store.receive(.sendRequest)

        await store.receive(.dequeCompletedResults(request)) {
            $0.flushing = true
            $0.requestsInFlight = [request2]
            $0.queue = []
        }
        await store.receive(.sendRequest)
        await store.receive(.dequeCompletedResults(request2)) {
            $0.flushing = false
            $0.requestsInFlight = []
            $0.queue = []
        }
    }

    func testFlushQueueDuringExponentialBackoff() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200)
        initialState.flushing = false
        let request = try initialState.buildProfileRequest()
        let request2 = try initialState.buildTokenRequest()
        initialState.queue = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.retryInfo = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200 - Int(initialState.flushInterval))
        }
    }

    func testFlushQueueExponentialBackoffGoesToSize() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryInfo = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: Int(initialState.flushInterval) - 2)
        initialState.flushing = false
        let request = try initialState.buildProfileRequest()
        let request2 = try initialState.buildTokenRequest()
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
        await store.receive(.dequeCompletedResults(request)) {
            $0.flushing = false
            $0.retryInfo = .retry(0)
            $0.requestsInFlight = []
            $0.queue = []
        }
    }

    func testSendRequestWhenNotFlushing() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest)
    }

    // MARK: - send request

    func testSendRequestWithNoRequestsInFlight() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        // Shouldn't really happen but getting more coverage...
        _ = await store.send(.sendRequest) {
            $0.flushing = false
        }
    }

    // MARK: - Network Connectivity Changed

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
            $0.flushInterval = WIFI_FLUSH_INTERVAL
        }
        await store.receive(.flushQueue)
        _ = await store.send(.networkConnectivityChanged(.reachableViaWWAN)) {
            $0.flushInterval = CELLULAR_FLUSH_INTERVAL
        }
        await store.receive(.flushQueue)
    }

    // MARK: - Stop

    func testStopWithRequestsInFlight() async throws {
        // This test is a little convoluted but essentially want to make when we stop
        // that we save our state.
        var initialState = INITIALIZED_TEST_STATE()
        let request = try initialState.buildProfileRequest()
        let request2 = try initialState.buildTokenRequest()
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

    func testFlushWithPendingProfile() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let profileActions: [(Profile.ProfileKey, Any)] = [
            (.city, "Sharon"),
            (.region, "New England"),
            (.address1, "123 Main Street"),
            (.address2, "Apt 6"),
            (.zip, "02067"),
            (.country, "Mexico"),
            (.latitude, 23.0),
            (.longitude, 46.0),
            (.title, "King"),
            (.organization, "Klaviyo"),
            (.firstName, "Jeffrey"),
            (.lastName, "Lebowski"),
            (.image, "foto.png"),
            (.custom(customKey: "foo"), 20)
        ]

        var pendingProfile = [Profile.ProfileKey: AnyEncodable]()

        for (key, value) in profileActions {
            pendingProfile[key] = AnyEncodable(value)
            _ = await store.send(.setProfileProperty(key, AnyEncodable(value))) {
                $0.pendingProfile = pendingProfile
            }
        }

        var request: KlaviyoAPI.KlaviyoRequest?
        _ = await store.send(.flushQueue) {
            $0.enqueueProfileRequest()
            $0.requestsInFlight = $0.queue
            $0.queue = []
            $0.flushing = true
            request = $0.requestsInFlight[0]
        }

        await store.receive(.sendRequest)
        await store.receive(.dequeCompletedResults(request!)) {
            $0.requestsInFlight = $0.queue
            $0.flushing = false
        }
    }

    // MARK: - Test set profile

    func testSetProfileWithExistingProperties() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.enqueueProfile(Profile(email: "foo"))) {
            $0.phoneNumber = nil
            $0.email = "foo"
            $0.pushToken = nil
            $0.enqueueProfileRequest()
        }
    }

    // MARK: - Test enqueue event

    func testEnqueueEvent() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "555BLOB"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        let event = Event(name: .OpenedPush, properties: ["push_token": initialState.pushToken!], profile: ["$email": "foo", "$phone_number": "666BLOB", "$id": "my_user_id"])
        _ = await store.send(.enqueueEvent(event)) {
            $0.email = "foo"
            $0.phoneNumber = "666BLOB"
            $0.externalId = "my_user_id"
            try $0.enqueueRequest(request: .init(apiKey: XCTUnwrap($0.apiKey), endpoint: .createEvent(.init(data: .init(event: event, anonymousId: XCTUnwrap($0.anonymousId))))))
        }
    }
}
