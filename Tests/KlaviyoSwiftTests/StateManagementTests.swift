//
//  StateManagementTests.swift
//
//
//  Created by Noah Durell on 12/6/22.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import AnyCodable
import Combine
import Foundation
import XCTest

class StateManagementTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        BadgeManager.resetToProduction()
    }

    @MainActor
    override func tearDown() async throws {
        BadgeManager.resetToProduction()
    }

    // MARK: - Initialization

    @MainActor
    func testInitialize() async throws {
        let setBadgeExpectation = expectation(description: "BadgeManager.setBadgeCount(0) called on start")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }

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
        await fulfillment(of: [setBadgeExpectation], timeout: 1)
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
            enablement: .authorized
        )

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
                deviceData: initialState.pushTokenData!.deviceData
            )
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
            enablement: .authorized
        )

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
        initialState.retryState = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200)
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        initialState.queue = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.retryState = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: 200 - Int(initialState.flushInterval))
        }
    }

    @MainActor
    func testFlushQueueExponentialBackoffGoesToSize() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.retryState = .retryWithBackoff(requestCount: 23, totalRetryCount: 23, currentBackoff: Int(initialState.flushInterval) - 2)
        initialState.flushing = false
        let request = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let request2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "blob_token", enablement: .authorized)
        initialState.queue = [request, request2]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        _ = await store.send(.flushQueue) {
            $0.retryState = .retry(23)
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
        }
        await store.receive(.sendRequest)

        // didn't fake uuid since we are not testing this.
        await store.receive(.deQueueCompletedResults(request)) {
            $0.flushing = false
            $0.retryState = .retry(1)
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
        let syncExpectation = expectation(description: "BadgeManager.syncBadgeCount called on stop")
        BadgeManager.syncBadgeCountSpy = { syncExpectation.fulfill() }

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
        await fulfillment(of: [syncExpectation], timeout: 1)
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
            case let .registerPushToken(_, payload):
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
            // No reset — state had no prior identifiers (isIdentified = false),
            // so pushTokenData stays on state.

            let request = KlaviyoRequest(
                endpoint: .registerPushToken(
                    initialState.apiKey!,
                    PushTokenPayload(
                        pushToken: initialState.pushTokenData!.pushToken,
                        enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                        background: initialState.pushTokenData!.pushBackground.rawValue,
                        profile: ProfilePayload(
                            Profile.test,
                            anonymousId: initialState.anonymousId!
                        )
                    )
                )
            )
            $0.queue = [request]
        }
    }

    @MainActor
    func testCreateProfileWithTrailingWhitespaceProperties() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        _ = await store.send(.enqueueProfile(Profile(email: "foo@blob.com ", phoneNumber: "+19999999999     ", externalId: "abcdefg    "))) {
            $0.phoneNumber = "+19999999999"
            $0.email = "foo@blob.com"
            $0.externalId = "abcdefg"
            // No reset — state had no prior identifiers (isIdentified = false),
            // so pushTokenData stays on state. The reducer builds the request inline
            // using the captured pushTokenData without clearing it from state.
            let request = KlaviyoRequest(
                endpoint: .registerPushToken(
                    initialState.apiKey!,
                    PushTokenPayload(
                        pushToken: initialState.pushTokenData!.pushToken,
                        enablement: initialState.pushTokenData!.pushEnablement.rawValue,
                        background: initialState.pushTokenData!.pushBackground.rawValue,
                        profile: ProfilePayload(
                            Profile(email: "foo@blob.com", phoneNumber: "+19999999999", externalId: "abcdefg"),
                            anonymousId: $0.anonymousId!
                        )
                    )
                )
            )
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
            // High-priority events use the package init so that priority flows onto the request.
            let isHighPriority = eventName == ._openedPush
            let event = isHighPriority
                ? Event(
                    name: eventName,
                    properties: ["push_token": initialState.pushTokenData!.pushToken],
                    priority: .high
                )
                : Event(name: eventName, properties: ["push_token": initialState.pushTokenData!.pushToken])
            let expectedPriority: RequestPriority = isHighPriority ? .high : .standard
            await store.send(.enqueueEvent(event)) {
                let request = try KlaviyoRequest(
                    endpoint: .createEvent(
                        XCTUnwrap($0.apiKey),
                        CreateEventPayload(
                            data: CreateEventPayload.Event(
                                name: eventName.value,
                                properties: event.properties,
                                phoneNumber: $0.phoneNumber,
                                anonymousId: initialState.anonymousId!,
                                time: event.time,
                                pushToken: initialState.pushTokenData!.pushToken
                            )
                        )
                    ),
                    priority: expectedPriority
                )
                if isHighPriority {
                    $0.queue.insert(request, at: 0)
                } else {
                    $0.enqueueRequest(request: request)
                }
            }

            // High-priority events trigger an immediate flush; all others flush on the regular interval.
            if isHighPriority {
                await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
            }
        }
    }

    @MainActor
    func testEnqueueEventWhenInitilizingSendsEvent() async throws {
        let setBadgeExpectation = expectation(description: "BadgeManager.setBadgeCount(0) called on start")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }

        let initialState = INITILIZING_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let event = Event(name: .openedAppMetric)
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
                    endpoint: .createEvent(
                        XCTUnwrap($0.apiKey),
                        CreateEventPayload(
                            data: CreateEventPayload.Event(
                                name: Event.EventName.openedAppMetric.value,
                                properties: event.properties,
                                phoneNumber: $0.phoneNumber,
                                anonymousId: initialState.anonymousId!,
                                time: event.time
                            )
                        )
                    )
                )
            )
        }

        await store.receive(.start, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.setPushEnablement(PushEnablement.authorized), timeout: TIMEOUT_NANOSECONDS)
        await fulfillment(of: [setBadgeExpectation], timeout: 1)
    }

    // MARK: - Test enqueue aggregate event

    @MainActor
    func testEnqueueAggregateEvent() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let data = Data()
        await store.send(.enqueueAggregateEvent(data)) {
            try $0.enqueueRequest(
                request: KlaviyoRequest(
                    endpoint: .aggregateEvent(
                        XCTUnwrap($0.apiKey),
                        AggregateEventPayload(data)
                    )
                )
            )
        }
    }

    @MainActor
    func testEnqueueAggregateEventWhenInitilizingSendsEvent() async throws {
        let setBadgeExpectation = expectation(description: "BadgeManager.setBadgeCount(0) called on start")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }

        let initialState = INITILIZING_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let data = Data()
        await store.send(.enqueueAggregateEvent(data)) {
            $0.pendingRequests = [KlaviyoState.PendingRequest.aggregateEvent(data)]
        }

        await store.send(.completeInitialization(initialState)) {
            $0.pendingRequests = []
            $0.initalizationState = .initialized
        }

        await store.receive(.enqueueAggregateEvent(data), timeout: TIMEOUT_NANOSECONDS) {
            try $0.enqueueRequest(
                request: KlaviyoRequest(
                    endpoint: .aggregateEvent(
                        XCTUnwrap($0.apiKey),
                        AggregateEventPayload(data)
                    )
                )
            )
        }

        await store.receive(.start, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.setPushEnablement(PushEnablement.authorized), timeout: TIMEOUT_NANOSECONDS)
        await fulfillment(of: [setBadgeExpectation], timeout: 1)
    }

    @MainActor
    func testPrioritizedEventsAreInsertedAtFrontOfQueue() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false

        // Add some existing requests to the queue
        let existingRequest1 = initialState.buildProfileRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!)
        let existingRequest2 = initialState.buildTokenRequest(apiKey: initialState.apiKey!, anonymousId: initialState.anonymousId!, pushToken: "token1", enablement: .authorized)
        initialState.queue = [existingRequest1, existingRequest2]

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Test geofence event is inserted at front.
        // Geofence events set priority: .high at the producer site; mirror that here.
        let geofenceEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "test-location-id"],
            priority: .high
        )

        var geofenceRequest: KlaviyoRequest?
        await store.send(.enqueueEvent(geofenceEvent)) {
            // Geofence event is prioritized, so it should be inserted at index 0
            geofenceRequest = try KlaviyoRequest(
                endpoint: .createEvent(
                    XCTUnwrap($0.apiKey),
                    CreateEventPayload(
                        data: CreateEventPayload.Event(
                            name: geofenceEvent.metric.name.value,
                            properties: geofenceEvent.properties,
                            phoneNumber: $0.phoneNumber,
                            anonymousId: initialState.anonymousId!,
                            time: geofenceEvent.time,
                            pushToken: $0.pushTokenData?.pushToken
                        )
                    )
                ),
                priority: .high
            )
            $0.queue.insert(geofenceRequest!, at: 0)
        }

        var actualGeofenceRequest: KlaviyoRequest?
        await store.receive(.flushQueue) {
            $0.flushing = true
            $0.requestsInFlight = $0.queue
            $0.queue = []
            XCTAssertEqual($0.requestsInFlight.count, 3, "Should have 3 requests in flight")
            actualGeofenceRequest = $0.requestsInFlight[0]
            if case let .createEvent(_, payload) = actualGeofenceRequest!.endpoint {
                XCTAssertEqual(payload.data.attributes.metric.data.attributes.name, "$geofence_enter", "First request in flight should be geofence event")
            } else {
                XCTFail("First request in flight should be geofence event")
            }
            XCTAssertEqual($0.requestsInFlight[1].id, existingRequest1.id, "Second request should be existing request 1")
            XCTAssertEqual($0.requestsInFlight[2].id, existingRequest2.id, "Third request should be existing request 2")
        }
        await store.receive(.sendRequest)
        await store.receive(.deQueueCompletedResults(actualGeofenceRequest!)) {
            $0.requestsInFlight.removeAll { $0.id == actualGeofenceRequest!.id }
            $0.retryState = .retry(1)
            $0.flushing = false
        }
    }

    // MARK: - enqueueSubscription

    /// Builds the `KlaviyoRequest` a subscription enqueue is expected to produce.
    private func expectedSubscriptionRequest(
        apiKey: String,
        listId: String = "list-123",
        profile: ProfilePayload
    ) -> KlaviyoRequest {
        KlaviyoRequest(
            endpoint: .createSubscription(apiKey, CreateSubscriptionPayload(listId: listId, profile: profile))
        )
    }

    @MainActor
    func testEnqueueSubscription() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(email: "test@example.com", anonymousId: anonymousId)
        )

        await store.send(.enqueueSubscription(subscription)) {
            $0.enqueueRequest(request: request)
        }
    }

    @MainActor
    func testEnqueueSubscriptionWithChannels() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        initialState.phoneNumber = "+15005550006"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        let subscription = Subscription(
            listId: "list-123",
            channels: .init(email: .marketing, sms: .marketing)
        )
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(
                email: "test@example.com",
                phoneNumber: "+15005550006",
                subscriptions: SubscriptionChannels(
                    email: EmailConsent(marketing: .subscribed),
                    sms: MarketingTransactionalConsent(marketing: .subscribed)
                ),
                anonymousId: anonymousId
            )
        )

        await store.send(.enqueueSubscription(subscription)) {
            $0.enqueueRequest(request: request)
        }
    }

    /// Overrides `environment.emitDeveloperWarning` with an expectation that fulfills only when a
    /// warning containing `fragment` fires, pinning down which guard in enqueueSubscription was taken.
    @MainActor
    private func expectSubscriptionWarning(
        containing fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "developer warning containing: \(fragment)")
        environment.emitDeveloperWarning = { message in
            XCTAssertTrue(
                message.contains(fragment),
                "expected warning containing \"\(fragment)\" but got \"\(message)\"",
                file: file,
                line: line
            )
            expectation.fulfill()
        }
        return expectation
    }

    @MainActor
    func testEnqueueSubscriptionWhenInitializingReplaysAfterCompleteInitialization() async throws {
        var initialState = INITILIZING_TEST_STATE()
        initialState.email = "test@example.com"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(email: "test@example.com", anonymousId: anonymousId)
        )

        await store.send(.enqueueSubscription(subscription)) {
            $0.pendingRequests = [.subscription(subscription)]
        }

        await store.send(.completeInitialization(initialState)) {
            $0.pendingRequests = []
            $0.initalizationState = .initialized
        }

        await store.receive(.enqueueSubscription(subscription), timeout: TIMEOUT_NANOSECONDS) {
            $0.enqueueRequest(request: request)
        }

        await store.receive(.start, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.setPushEnablement(PushEnablement.authorized), timeout: TIMEOUT_NANOSECONDS)
    }

    @MainActor
    func testEnqueueSubscriptionMissingIdentifiersDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "at least one identifier")
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription.allAvailableMarketing(listId: "list-123")))
        await fulfillment(of: [expectation])
        XCTAssertTrue(store.state.queue.isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionPendingSetEmailBeforeSubscriptionSucceedsOnReplay() async throws {
        let initialState = INITILIZING_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        let email = "test@example.com"
        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")

        var stateWithEmail = initialState
        stateWithEmail.email = email
        let profileRequest = stateWithEmail.buildProfileRequest(apiKey: apiKey, anonymousId: anonymousId)
        let subscriptionRequest = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(email: email, anonymousId: anonymousId)
        )

        await store.send(.setEmail(email)) {
            $0.pendingRequests = [.setEmail(email)]
        }
        await store.send(.enqueueSubscription(subscription)) {
            $0.pendingRequests = [.setEmail(email), .subscription(subscription)]
        }

        await store.send(.completeInitialization(initialState)) {
            $0.pendingRequests = []
            $0.initalizationState = .initialized
        }

        await store.receive(.setEmail(email), timeout: TIMEOUT_NANOSECONDS) {
            $0.email = email
            $0.enqueueRequest(request: profileRequest)
        }

        await store.receive(.enqueueSubscription(subscription), timeout: TIMEOUT_NANOSECONDS) {
            $0.enqueueRequest(request: subscriptionRequest)
        }

        await store.receive(.start, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.setPushEnablement(PushEnablement.authorized), timeout: TIMEOUT_NANOSECONDS)
    }

    @MainActor
    func testEnqueueSubscriptionPendingSubscriptionBeforeSetEmailDropsSubscriptionOnReplay() async throws {
        let expectation = expectSubscriptionWarning(containing: "at least one identifier")
        let initialState = INITILIZING_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        let email = "test@example.com"
        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")

        var stateWithEmail = initialState
        stateWithEmail.email = email
        let profileRequest = stateWithEmail.buildProfileRequest(apiKey: apiKey, anonymousId: anonymousId)

        await store.send(.enqueueSubscription(subscription)) {
            $0.pendingRequests = [.subscription(subscription)]
        }
        await store.send(.setEmail(email)) {
            $0.pendingRequests = [.subscription(subscription), .setEmail(email)]
        }

        await store.send(.completeInitialization(initialState)) {
            $0.pendingRequests = []
            $0.initalizationState = .initialized
        }

        // FIFO: subscription replays before setEmail, so identifier validation fails.
        await store.receive(.enqueueSubscription(subscription), timeout: TIMEOUT_NANOSECONDS)
        await fulfillment(of: [expectation])

        await store.receive(.setEmail(email), timeout: TIMEOUT_NANOSECONDS) {
            $0.email = email
            $0.enqueueRequest(request: profileRequest)
        }

        XCTAssertFalse(
            store.state.queue.contains { request in
                if case .createSubscription = request.endpoint { return true }
                return false
            }
        )

        await store.receive(.start, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.flushQueue, timeout: TIMEOUT_NANOSECONDS)
        await store.receive(.setPushEnablement(PushEnablement.authorized), timeout: TIMEOUT_NANOSECONDS)
    }

    @MainActor
    func testEnqueueSubscriptionAllAvailableMarketingWithPhoneOnly() async throws {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "+15005550006"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let apiKey = try XCTUnwrap(initialState.apiKey)
        let anonymousId = try XCTUnwrap(initialState.anonymousId)
        let subscription = Subscription.allAvailableMarketing(listId: "list-123")
        let request = expectedSubscriptionRequest(
            apiKey: apiKey,
            profile: ProfilePayload(phoneNumber: "+15005550006", anonymousId: anonymousId)
        )

        await store.send(.enqueueSubscription(subscription)) {
            $0.enqueueRequest(request: request)
        }
    }

    @MainActor
    func testEnqueueSubscriptionEmptyChannelsDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "none were enabled")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init())))
        await fulfillment(of: [expectation])
        XCTAssertTrue(store.state.queue.isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionEmailChannelWithoutEmailDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "requires an email")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.phoneNumber = "+15005550006"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init(email: .marketing))))
        await fulfillment(of: [expectation])
        XCTAssertTrue(store.state.queue.isEmpty)
    }

    @MainActor
    func testEnqueueSubscriptionPhoneChannelWithoutPhoneDoesNotEnqueue() async throws {
        let expectation = expectSubscriptionWarning(containing: "requires a phone number")
        var initialState = INITIALIZED_TEST_STATE()
        initialState.email = "test@example.com"
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        await store.send(.enqueueSubscription(Subscription(listId: "list-123", channels: .init(sms: .marketing))))
        await fulfillment(of: [expectation])
        XCTAssertTrue(store.state.queue.isEmpty)
    }

    // MARK: - Request priority

    /// Concrete `TestStore` type produced by ``makePriorityTestStore()``.
    private typealias PriorityTestStore = TestStore<
        KlaviyoState, KlaviyoAction, KlaviyoState, KlaviyoAction, Void
    >

    /// Builds a non-flushing store seeded with a single standard-priority queued request,
    /// so front-insertion (high priority) vs. append (standard) is observable. Returns the
    /// store together with the seeded request for identity assertions.
    @MainActor
    private func makePriorityTestStore() -> (store: PriorityTestStore, seededRequest: KlaviyoRequest) {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        let existingRequest = initialState.buildProfileRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!
        )
        initialState.queue = [existingRequest]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        return (store, existingRequest)
    }

    @MainActor
    func testOpenedPushEventProducesHighPriorityRequestAtQueueFront() async throws {
        let (store, _) = makePriorityTestStore()
        // Assert only the priority/front-insert/flush contract; the full network flush
        // chain is exercised by testPrioritizedEventsAreInsertedAtFrontOfQueue.
        store.exhaustivity = .off

        let event = Event(name: ._openedPush, properties: ["foo": "bar"], priority: .high)
        await store.send(.enqueueEvent(event))

        XCTAssertEqual(store.state.queue.count, 2, "Existing + new request should be queued")
        XCTAssertEqual(
            store.state.queue[0].priority,
            .high,
            "Opened-push request must carry .high priority and be inserted at the front"
        )

        await store.receive(.flushQueue)
    }

    @MainActor
    func testGeofenceEventProducesHighPriorityRequestAtQueueFront() async throws {
        let (store, _) = makePriorityTestStore()
        // Assert only the priority/front-insert/flush contract; the full network flush
        // chain is exercised by testPrioritizedEventsAreInsertedAtFrontOfQueue.
        store.exhaustivity = .off

        let event = Event(
            name: .locationEvent(.geofenceEnter),
            properties: ["$geofence_id": "region-123"],
            priority: .high
        )
        await store.send(.enqueueEvent(event))

        XCTAssertEqual(store.state.queue.count, 2, "Existing + new request should be queued")
        XCTAssertEqual(
            store.state.queue[0].priority,
            .high,
            "Geofence request must carry .high priority and be inserted at the front"
        )

        await store.receive(.flushQueue)
    }

    @MainActor
    func testStandardEventProducesStandardPriorityRequestAppendedToQueue() async throws {
        let (store, existingRequest) = makePriorityTestStore()

        let event = Event(name: .openedAppMetric)
        await store.send(.enqueueEvent(event)) {
            let request = try KlaviyoRequest(
                endpoint: .createEvent(
                    XCTUnwrap($0.apiKey),
                    CreateEventPayload(
                        data: CreateEventPayload.Event(
                            name: Event.EventName.openedAppMetric.value,
                            properties: event.properties,
                            phoneNumber: $0.phoneNumber,
                            anonymousId: $0.anonymousId!,
                            time: event.time,
                            pushToken: $0.pushTokenData?.pushToken
                        )
                    )
                ),
                priority: .standard
            )
            // Standard request is appended; existing request stays at front
            $0.queue.append(request)
            XCTAssertEqual($0.queue[0].id, existingRequest.id, "Existing request should remain at queue[0]")
            XCTAssertEqual($0.queue.last?.priority, .standard, "Standard event produces .standard request")
        }
        // No flushQueue emitted for standard-priority events
    }
}
