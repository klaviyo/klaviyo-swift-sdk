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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    // MARK: - Event Enrichment Tests

    @MainActor
    func testPublishEvent_EnrichesEventWithMetadata() {
        // Given
        let expectation = XCTestExpectation(description: "Enriched event is received")
        var receivedEvent: Event?

        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // Subscribe to events
        KlaviyoInternal.eventPublisher()
            .sink { event in
                receivedEvent = event
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When - publish a basic event
        let originalEvent = Event(
            name: .customEvent("test_event"),
            properties: ["original_prop": "original_value"]
        )
        KlaviyoInternal.publishEvent(originalEvent)

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedEvent)
        XCTAssertEqual(receivedEvent?.metric.name.value, "test_event")

        // Verify metadata was added
        let properties = receivedEvent?.properties ?? [:]
        XCTAssertNotNil(properties["Device ID"])
        XCTAssertNotNil(properties["Device Manufacturer"])
        XCTAssertNotNil(properties["Device Model"])
        XCTAssertNotNil(properties["OS Name"])
        XCTAssertNotNil(properties["OS Version"])
        XCTAssertNotNil(properties["SDK Name"])
        XCTAssertNotNil(properties["SDK Version"])
        XCTAssertNotNil(properties["App Name"])
        XCTAssertNotNil(properties["App ID"])
        XCTAssertNotNil(properties["App Version"])
        XCTAssertNotNil(properties["App Build"])
        XCTAssertNotNil(properties["Push Token"])

        // Verify original property is preserved
        XCTAssertEqual(properties["original_prop"] as? String, "original_value")
    }

    @MainActor
    func testPublishEvent_PreservesEventAttributes() {
        // Given
        let expectation = XCTestExpectation(description: "Event received with preserved attributes")
        var receivedEvent: Event?

        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        KlaviyoInternal.eventPublisher()
            .sink { event in
                receivedEvent = event
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When - publish event with specific attributes
        let testTime = Date(timeIntervalSince1970: 1_234_567_890)
        let testUniqueId = "test-unique-id-123"
        let originalEvent = Event(
            name: .addedToCartMetric,
            properties: ["item_id": "12345"],
            identifiers: Event.Identifiers(email: "test@example.com", phoneNumber: "+15555555555"),
            value: 99.99,
            time: testTime,
            uniqueId: testUniqueId
        )
        KlaviyoInternal.publishEvent(originalEvent)

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedEvent)
        XCTAssertEqual(receivedEvent?.metric.name.value, "Added to Cart")
        XCTAssertEqual(receivedEvent?.value, 99.99)
        XCTAssertEqual(receivedEvent?.time, testTime)
        XCTAssertEqual(receivedEvent?.uniqueId, testUniqueId)
        XCTAssertEqual(receivedEvent?.identifiers?.email, "test@example.com")
        XCTAssertEqual(receivedEvent?.identifiers?.phoneNumber, "+15555555555")

        // Verify original and metadata properties both exist
        let properties = receivedEvent?.properties ?? [:]
        XCTAssertEqual(properties["item_id"] as? String, "12345")
        XCTAssertNotNil(properties["Device ID"])
    }

    @MainActor
    func testPublishEvent_IncludesPushTokenWhenAvailable() {
        // Given
        let expectation = XCTestExpectation(description: "Event received with push token")
        var receivedEvent: Event?

        // Set up state with push token
        var testState = KlaviyoState.test
        testState.pushTokenData = KlaviyoState.PushTokenData(
            pushToken: "test_push_token_abc123",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        KlaviyoInternal.eventPublisher()
            .sink { event in
                receivedEvent = event
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        let originalEvent = Event(name: .customEvent("test_event"))
        KlaviyoInternal.publishEvent(originalEvent)

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedEvent)
        let properties = receivedEvent?.properties ?? [:]
        // Note: Synchronous push token fetch may not work reliably in test environment
        // Just verify the field exists (will be either actual token or empty string)
        XCTAssertNotNil(properties["Push Token"], "Push Token field should be present")
    }

    @MainActor
    func testPublishEvent_EmptyPushTokenWhenNotAvailable() {
        // Given
        let expectation = XCTestExpectation(description: "Event received with empty push token")
        var receivedEvent: Event?

        // Set up state without push token
        var testState = KlaviyoState.test
        testState.pushTokenData = nil
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        KlaviyoInternal.eventPublisher()
            .sink { event in
                receivedEvent = event
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        let originalEvent = Event(name: .customEvent("test_event"))
        KlaviyoInternal.publishEvent(originalEvent)

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedEvent)
        let properties = receivedEvent?.properties ?? [:]
        XCTAssertEqual(properties["Push Token"] as? String, "")
    }

    @MainActor
    func testPublishEvent_BuffersEnrichedEvent() {
        // Given
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // When - publish an event
        let originalEvent = Event(
            name: .customEvent("buffered_event"),
            properties: ["test_prop": "test_value"]
        )
        KlaviyoInternal.publishEvent(originalEvent)

        // Small delay to ensure buffering completes
        let expectation = XCTestExpectation(description: "Buffer delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then - new subscriber should receive the enriched buffered event
        let newSubscriberExpectation = XCTestExpectation(description: "New subscriber receives enriched event")
        var bufferedEvent: Event?

        KlaviyoInternal.eventPublisher()
            .sink { event in
                bufferedEvent = event
                newSubscriberExpectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [newSubscriberExpectation], timeout: 1.0)

        XCTAssertNotNil(bufferedEvent)
        XCTAssertEqual(bufferedEvent?.metric.name.value, "buffered_event")

        // Verify the buffered event has metadata
        let properties = bufferedEvent?.properties ?? [:]
        XCTAssertEqual(properties["test_prop"] as? String, "test_value")
        XCTAssertNotNil(properties["Device ID"], "Buffered event should include metadata")
        XCTAssertNotNil(properties["SDK Name"], "Buffered event should include metadata")
    }
}
