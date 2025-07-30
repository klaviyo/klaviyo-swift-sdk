//
//  KlaviyoInternalTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/22/25.
//

import Combine
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import KlaviyoCore

final class KlaviyoInternalTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    @MainActor
    override func tearDownWithError() throws {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
    }

    // MARK: - Profile Data Tests

    @MainActor
    func testProfileChangePublisherEmitsCorrectData() throws {
        let expectation = XCTestExpectation(description: "Profile data is emitted")
        var receivedResult: KlaviyoInternal.ProfileDataResult?

        // Set up test environment
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // Subscribe to the publisher
        KlaviyoInternal.profileChangePublisher()
            .sink { result in
                receivedResult = result
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Trigger a profile change
        _ = testStore.send(.setEmail("a@b.com"))
        _ = testStore.send(.setPhoneNumber("+15555555555"))
        _ = testStore.send(.setExternalId("test123"))

        // Wait for the expectation
        wait(for: [expectation], timeout: 1.0)

        // Verify the emitted profile data
        if case let .success(profileData) = receivedResult {
            XCTAssertEqual(profileData.email, "a@b.com")
            XCTAssertEqual(profileData.phoneNumber, "+15555555555")
            XCTAssertEqual(profileData.externalId, "test123")
        } else {
            XCTFail("Expected success case but got \(String(describing: receivedResult))")
        }
    }

    @MainActor
    func testRemoveDuplicates() throws {
        let expectation = XCTestExpectation(description: "Profile data is emitted")
        var receiveValueCount = 0

        // Set up test environment
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let initialEmail = try XCTUnwrap(KlaviyoState.test.email)

        // Subscribe to the publisher
        KlaviyoInternal.profileChangePublisher()
            .sink { _ in
                receiveValueCount += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // receiveValueCount should be 1 at this point because `profileChangePublisher`
        // will get an initial value when it receives a subscription.
        XCTAssertEqual(receiveValueCount, 1)

        // Trigger a profile change
        _ = testStore.send(.setEmail(initialEmail))

        // receiveValueCount should stay at 1 because we
        // set the email to the same as its initial value
        XCTAssertEqual(receiveValueCount, 1)

        // Wait for the expectation
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testFetchProfileData_returnsProfileDataWhenInitialized() async throws {
        // Set up test environment with initialized state
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let profileData = try await KlaviyoInternal.fetchProfileData()

        XCTAssertEqual(profileData.email, KlaviyoState.test.email)
        XCTAssertEqual(profileData.phoneNumber, KlaviyoState.test.phoneNumber)
        XCTAssertEqual(profileData.externalId, KlaviyoState.test.externalId)
    }

    @MainActor
    func testFetchProfileData_throwsWhenUninitialized() async {
        // Set up test environment with uninitialized state
        let initialState = KlaviyoState(queue: [], initalizationState: .uninitialized)
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        do {
            _ = try await KlaviyoInternal.fetchProfileData()
            XCTFail("Expected fetchProfileData to throw")
        } catch {
            XCTAssertEqual(error as? SDKError, .notInitialized)
        }
    }

    @MainActor
    func testResetProfileDataSubject() {
        let expectation = XCTestExpectation(description: "Profile data subject is reset")
        var receivedError: SDKError?

        // First initialize the subject
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // Subscribe to see the reset state
        KlaviyoInternal.profileChangePublisher()
            .sink { result in
                if case let .failure(error) = result {
                    receivedError = error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Reset the subject
        KlaviyoInternal.resetProfileDataSubject()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedError, .notInitialized)
    }

    // MARK: - API Key Tests

    func testApiKeyPublisher_emitsValidKeyImmediately() {
        let expectation = XCTestExpectation(description: "Should receive valid key immediately")
        var receivedValues: [String] = []

        // Set up the test environment with a valid key and initialized state
        let initialState = KlaviyoState(
            apiKey: "ABC123",
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        KlaviyoInternal.apiKeyPublisher()
            .sink { result in
                switch result {
                case let .success(apiKey):
                    receivedValues.append(apiKey)
                    expectation.fulfill()
                case .failure:
                    XCTFail("expected apiKeyPublisher to emit a `success` value with a valid API key")
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, ["ABC123"])
    }

    func testApiKeyPublisher_emitsMultipleValues() {
        let expectation = XCTestExpectation(description: "Publisher should emit two API keys")
        var receivedValues = Set<String>()

        // Set up the test environment with a valid key
        let initialState = KlaviyoState(queue: [])
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        KlaviyoInternal.apiKeyPublisher()
            .sink { result in
                if case let .success(apiKey) = result {
                    receivedValues.insert(apiKey)
                    if receivedValues.count == 2 {
                        expectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = testStore.send(.initialize("ABC123"))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            _ = testStore.send(.initialize("DEF456"))
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, Set<String>(["ABC123", "DEF456"]))
    }

    func testApiKeyPublisher_nilAPIKeyEmitsFailure() async {
        // Set up the test environment with a nil key but initialized state
        let initialState = KlaviyoState(
            apiKey: nil,
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let expectation = XCTestExpectation(description: "apiKeyPublisher to emit a `failure` value with error SDKError.apiKeyNilOrEmpty")
        var receivedError: SDKError?

        KlaviyoInternal.apiKeyPublisher()
            .sink { result in
                switch result {
                case .success:
                    XCTFail("Expected apiKeyPublisher to emit a failure value")
                case let .failure(error):
                    receivedError = error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedError, .apiKeyNilOrEmpty)
    }

    func testApiKeyPublisher_emptyAPIKeyEmitsFailure() async {
        // Set up the test environment with an empty key but initialized state
        let initialState = KlaviyoState(
            apiKey: "",
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let expectation = XCTestExpectation(description: "apiKeyPublisher to emit a `failure` value with error SDKError.apiKeyNilOrEmpty")
        var receivedError: SDKError?

        KlaviyoInternal.apiKeyPublisher()
            .sink { result in
                switch result {
                case .success:
                    XCTFail("Expected apiKeyPublisher to emit a failure value")
                case let .failure(error):
                    receivedError = error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedError, .apiKeyNilOrEmpty)
    }

    func testApiKeyPublisher_uninitializedEmitsFailure() async {
        // Set up the test environment with uninitialized state
        let initialState = KlaviyoState(
            apiKey: "ABC123",
            queue: [],
            initalizationState: .uninitialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let expectation = XCTestExpectation(description: "apiKeyPublisher to emit a `failure` value with error SDKError.notInitialized")
        var receivedError: SDKError?

        KlaviyoInternal.apiKeyPublisher()
            .sink { result in
                switch result {
                case .success:
                    XCTFail("Expected apiKeyPublisher to emit a failure value")
                case let .failure(error):
                    receivedError = error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedError, .notInitialized)
    }

    func testFetchAPIKey_returnsValidKey() async throws {
        // Set up test environment with valid API key
        let initialState = KlaviyoState(
            apiKey: "TEST123",
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        XCTAssertEqual(apiKey, "TEST123")
    }

    func testFetchAPIKey_throwsWhenUninitialized() async {
        // Set up test environment with uninitialized state
        let initialState = KlaviyoState(queue: [], initalizationState: .uninitialized)
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        do {
            _ = try await KlaviyoInternal.fetchAPIKey()
            XCTFail("Expected fetchAPIKey to throw")
        } catch {
            XCTAssertEqual(error as? SDKError, .notInitialized)
        }
    }

    func testFetchAPIKey_throwsWhenAPIKeyNil() async {
        // Set up test environment with nil API key
        let initialState = KlaviyoState(
            apiKey: nil,
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        do {
            _ = try await KlaviyoInternal.fetchAPIKey()
            XCTFail("Expected fetchAPIKey to throw")
        } catch {
            XCTAssertEqual(error as? SDKError, .apiKeyNilOrEmpty)
        }
    }

    func testFetchAPIKey_throwsWhenAPIKeyEmpty() async {
        // Set up test environment with empty API key
        let initialState = KlaviyoState(
            apiKey: "",
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        do {
            _ = try await KlaviyoInternal.fetchAPIKey()
            XCTFail("Expected fetchAPIKey to throw")
        } catch {
            XCTAssertEqual(error as? SDKError, .apiKeyNilOrEmpty)
        }
    }

    func testResetAPIKeySubject() {
        let expectation = XCTestExpectation(description: "API key subject is reset")
        var receivedError: SDKError?

        // First initialize the subject with a valid state
        let initialState = KlaviyoState(
            apiKey: "TEST123",
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // Subscribe to see the reset state
        KlaviyoInternal.apiKeyPublisher()
            .sink { result in
                if case let .failure(error) = result {
                    receivedError = error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Reset the subject
        KlaviyoInternal.resetAPIKeySubject()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedError, .notInitialized)
    }

    // MARK: - Aggregate Events Tests

//    @MainActor
//    func testCreateAggregateEvent() {
//        // Set up test environment
//        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
//        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
//
//        // Create a test aggregate event
//        let testEvent = AggregateEventPayload(
//            event: Event(data: EventData(type: .event, attributes: EventAttributes(eventName: "test_event"))),
//            profile: nil
//        )
//
//        // This should not throw - we're testing that the method can be called
//        XCTAssertNoThrow(KlaviyoInternal.create(aggregateEvent: testEvent))
//    }

    // MARK: - Event Publishing Tests

    @MainActor
    func testEventPublisher_emitsEventWithProperties() throws {
        // Given: Set up a mock to capture published events
        var publishedEvents: [Event] = []
        let initialState = KlaviyoState(
            apiKey: "test-api-key",
            anonymousId: "test-anonymous-id",
            queue: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
        KlaviyoInternal.eventPublisher()
            .sink { event in
                publishedEvents.append(event)
            }
            .store(in: &cancellables)

        // When
        let testEvent = Event(
            name: .addedToCartMetric,
            properties: ["amount": 99.99, "currency": "USD"]
        )
        _ = testStore.send(.enqueueEvent(testEvent))

        // Then
        XCTAssertEqual(publishedEvents.count, 1, "Should have published exactly one event")
        XCTAssertEqual(publishedEvents.first?.metric.name, .addedToCartMetric, "Should have published the correct event name")
        XCTAssertEqual(publishedEvents.first?.properties["amount"] as? Double, 99.99, "Should have published the correct properties")
        XCTAssertEqual(publishedEvents.first?.properties["currency"] as? String, "USD", "Should have published the correct properties")
    }

    // MARK: - Integration Tests

    @MainActor
    func testBothPublishersWorkIndependently() async throws {
        // Set up test environment
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // Subscribe to both publishers
        let profileExpectation = XCTestExpectation(description: "Profile data received")
        let apiKeyExpectation = XCTestExpectation(description: "API key received")

        var profileResult: KlaviyoInternal.ProfileDataResult?
        var apiKeyResult: KlaviyoInternal.APIKeyResult?

        KlaviyoInternal.profileChangePublisher()
            .sink { result in
                profileResult = result
                profileExpectation.fulfill()
            }
            .store(in: &cancellables)

        KlaviyoInternal.apiKeyPublisher()
            .sink { result in
                apiKeyResult = result
                apiKeyExpectation.fulfill()
            }
            .store(in: &cancellables)

        // Wait for both publishers to emit
        await fulfillment(of: [profileExpectation, apiKeyExpectation], timeout: 1.0)

        // Verify both publishers received values from the same state
        XCTAssertNotNil(profileResult)
        XCTAssertNotNil(apiKeyResult)

        if case .success = profileResult,
           case .success = apiKeyResult {
            // Both should succeed for the test state
        } else {
            XCTFail("Expected both publishers to emit success cases")
        }
    }
}
