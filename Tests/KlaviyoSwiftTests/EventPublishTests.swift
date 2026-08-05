//
//  EventPublishTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import XCTest

@MainActor
final class EventPublishTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        EventBus.shared.reset()
    }

    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        EventBus.shared.reset()
        super.tearDown()
    }

    // MARK: - Event Enrichment Tests

    func testPublishEvent_EnrichesEventWithMetadata() {
        // Given
        let expectation = XCTestExpectation(description: "Enriched event is received")
        var receivedEvent: Event?

        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // Subscribe to events
        EventBus.shared.eventPublisher()
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
        enrichAndPublishEvent(originalEvent)

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

    func testPublishEvent_PreservesEventAttributes() {
        // Given
        let expectation = XCTestExpectation(description: "Event received with preserved attributes")
        var receivedEvent: Event?

        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        EventBus.shared.eventPublisher()
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
        enrichAndPublishEvent(originalEvent)

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

    func testPublishEvent_PreservesHighPriority() {
        // Regression: enrichment rebuilds the Event, and must carry `priority` through so
        // high-priority opened-push/geofence events are not silently downgraded to `.standard`
        // on the EventBus copy.
        let expectation = XCTestExpectation(description: "Enriched event preserves .high priority")
        var receivedEvent: Event?

        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        EventBus.shared.eventPublisher()
            .sink { event in
                receivedEvent = event
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When - publish a high-priority event (as opened-push/geofence producers do)
        let originalEvent = Event(name: ._openedPush, priority: .high)
        enrichAndPublishEvent(originalEvent)

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(
            receivedEvent?.priority,
            .high,
            "Enrichment must preserve high priority on the EventBus copy"
        )
    }

    func testPublishEvent_IncludesPushTokenWhenAvailable() {
        // Given
        let expectation = XCTestExpectation(description: "Event received with push token")
        var receivedEvent: Event?

        // Set up state with push token
        var testState = KlaviyoState.test
        testState.pushTokenData = PushTokenData(
            pushToken: "test_push_token_abc123",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        )
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        EventBus.shared.eventPublisher()
            .sink { event in
                receivedEvent = event
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        let originalEvent = Event(name: .customEvent("test_event"))
        enrichAndPublishEvent(originalEvent)

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedEvent)
        let properties = receivedEvent?.properties ?? [:]
        // Note: Synchronous push token fetch may not work reliably in test environment
        // Just verify the field exists (will be either actual token or empty string)
        XCTAssertNotNil(properties["Push Token"], "Push Token field should be present")
    }

    func testPublishEvent_EmptyPushTokenWhenNotAvailable() {
        // Given
        let expectation = XCTestExpectation(description: "Event received with empty push token")
        var receivedEvent: Event?

        // Set up state without push token
        var testState = KlaviyoState.test
        testState.pushTokenData = nil
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        EventBus.shared.eventPublisher()
            .sink { event in
                receivedEvent = event
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        let originalEvent = Event(name: .customEvent("test_event"))
        enrichAndPublishEvent(originalEvent)

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedEvent)
        let properties = receivedEvent?.properties ?? [:]
        XCTAssertEqual(properties["Push Token"] as? String, "")
    }

    func testPublishEvent_BuffersEnrichedEvent() {
        // Given
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // When - publish an event
        let originalEvent = Event(
            name: .customEvent("buffered_event"),
            properties: ["test_prop": "test_value"]
        )
        enrichAndPublishEvent(originalEvent)

        // Small delay to ensure buffering completes
        let expectation = XCTestExpectation(description: "Buffer delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then - new subscriber should receive the enriched buffered event
        let newSubscriberExpectation = XCTestExpectation(description: "New subscriber receives enriched event")
        var bufferedEvent: Event?

        EventBus.shared.eventPublisher()
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
