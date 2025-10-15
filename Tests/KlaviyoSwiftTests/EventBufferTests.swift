//
//  EventBufferTests.swift
//  klaviyo-swift-sdk
//
//  Created by Ajay Subramanya on 10/7/25.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

class EventBufferTests: XCTestCase {
    var eventBuffer: EventBuffer!

    override func setUp() {
        super.setUp()
        eventBuffer = EventBuffer(maxBufferSize: 5, maxBufferAge: 2.0) // Small limits for testing
    }

    override func tearDown() {
        eventBuffer = nil
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testBufferStartsEmpty() {
        // When
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertTrue(events.isEmpty, "Buffer should start empty")
    }

    func testBufferStoresEvent() async throws {
        // Given
        let event = Event(name: .customEvent("test_event"))

        // When
        eventBuffer.buffer(event)

        // Wait for async buffer operation to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.metric.name.value, "test_event")
    }

    func testBufferStoresMultipleEvents() async throws {
        // Given
        let event1 = Event(name: .customEvent("event_1"))
        let event2 = Event(name: .customEvent("event_2"))
        let event3 = Event(name: .customEvent("event_3"))

        // When
        eventBuffer.buffer(event1)
        eventBuffer.buffer(event2)
        eventBuffer.buffer(event3)

        // Wait for async buffer operations to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].metric.name.value, "event_1")
        XCTAssertEqual(events[1].metric.name.value, "event_2")
        XCTAssertEqual(events[2].metric.name.value, "event_3")
    }

    // MARK: - Buffer Size Limit Tests

    func testBufferRespectsMaxSize() async throws {
        // Given - buffer with maxSize of 5
        let events = (1...7).map { Event(name: .customEvent("event_\($0)")) }

        // When - buffer 7 events
        events.forEach { eventBuffer.buffer($0) }

        // Wait for async buffer operations to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let recentEvents = eventBuffer.getRecentEvents()

        // Then - should only keep last 5
        XCTAssertEqual(recentEvents.count, 5, "Buffer should only keep last 5 events")
        XCTAssertEqual(recentEvents[0].metric.name.value, "event_3", "Should drop oldest events")
        XCTAssertEqual(recentEvents[4].metric.name.value, "event_7", "Should keep newest events")
    }

    func testBufferDropsOldestEventsWhenFull() async throws {
        // Given
        eventBuffer.buffer(Event(name: .customEvent("old_event")))

        // When - fill buffer to capacity
        for i in 1...5 {
            eventBuffer.buffer(Event(name: .customEvent("event_\(i)")))
        }

        // Wait for async buffer operations to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 5)
        XCTAssertFalse(events.contains { $0.metric.name.value == "old_event" }, "Old event should be dropped")
        XCTAssertTrue(events.contains { $0.metric.name.value == "event_5" }, "New events should be kept")
    }

    // MARK: - Buffer Age Limit Tests

    func testBufferFiltersOldEvents() async throws {
        // Given - buffer with 2 second age limit
        eventBuffer.buffer(Event(name: .customEvent("old_event")))

        // When - wait for event to expire
        try await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds

        eventBuffer.buffer(Event(name: .customEvent("new_event")))
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1, "Should only return recent event")
        XCTAssertEqual(events.first?.metric.name.value, "new_event")
    }

    func testBufferKeepsRecentEvents() async throws {
        // Given
        eventBuffer.buffer(Event(name: .customEvent("recent_event")))

        // When - wait less than age limit
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1, "Recent event should still be in buffer")
        XCTAssertEqual(events.first?.metric.name.value, "recent_event")
    }

    func testBufferMixesOldAndNewEvents() async throws {
        // Given
        eventBuffer.buffer(Event(name: .customEvent("old_event")))

        try await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds

        eventBuffer.buffer(Event(name: .customEvent("new_event_1")))
        eventBuffer.buffer(Event(name: .customEvent("new_event_2")))

        // Wait for async buffer operations to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // When
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 2, "Should only return recent events")
        XCTAssertTrue(events.contains { $0.metric.name.value == "new_event_1" })
        XCTAssertTrue(events.contains { $0.metric.name.value == "new_event_2" })
        XCTAssertFalse(events.contains { $0.metric.name.value == "old_event" })
    }

    // MARK: - Thread Safety Tests

    func testConcurrentBuffering() async throws {
        // Given
        let expectation = XCTestExpectation(description: "All events buffered")
        expectation.expectedFulfillmentCount = 100

        // When - buffer from multiple threads
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            eventBuffer.buffer(Event(name: .customEvent("event_\(index)")))
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // Then - should not crash and should have events
        let events = eventBuffer.getRecentEvents()
        XCTAssertGreaterThan(events.count, 0, "Should have buffered events")
        XCTAssertLessThanOrEqual(events.count, 5, "Should respect max buffer size")
    }

    func testConcurrentReadingAndWriting() async throws {
        // Given
        let writeExpectation = XCTestExpectation(description: "Writing complete")
        let readExpectation = XCTestExpectation(description: "Reading complete")

        // When - write and read concurrently
        DispatchQueue.global().async {
            for i in 0..<50 {
                self.eventBuffer.buffer(Event(name: .customEvent("event_\(i)")))
            }
            // Add small delay to allow async buffer operations to settle
            Thread.sleep(forTimeInterval: 0.1)
            writeExpectation.fulfill()
        }

        DispatchQueue.global().async {
            for _ in 0..<50 {
                _ = self.eventBuffer.getRecentEvents()
                // Add tiny delay between reads to prevent tight loop
                Thread.sleep(forTimeInterval: 0.001)
            }
            readExpectation.fulfill()
        }

        // Then - should not crash
        await fulfillment(of: [writeExpectation, readExpectation], timeout: 10.0)
        XCTAssertNoThrow(eventBuffer.getRecentEvents())
    }

    // MARK: - Edge Cases

    func testBufferWithZeroMaxSize() async throws {
        // Given
        let zeroBuffer = EventBuffer(maxBufferSize: 0, maxBufferAge: 10.0)

        // When
        zeroBuffer.buffer(Event(name: .customEvent("event")))

        // Wait for async buffer operation to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        let events = zeroBuffer.getRecentEvents()

        // Then
        XCTAssertTrue(events.isEmpty, "Buffer with size 0 should not store events")
    }

    func testBufferWithZeroMaxAge() async throws {
        // Given
        let zeroAgeBuffer = EventBuffer(maxBufferSize: 10, maxBufferAge: 0.0)

        // When
        zeroAgeBuffer.buffer(Event(name: .customEvent("event")))

        // Wait for async buffer operation to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        let events = zeroAgeBuffer.getRecentEvents()

        // Then
        XCTAssertTrue(events.isEmpty, "Buffer with age 0 should immediately expire events")
    }

    func testGetRecentEventsMultipleTimes() async throws {
        // Given
        eventBuffer.buffer(Event(name: .customEvent("event")))

        // Wait for async buffer operation to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // When
        let events1 = eventBuffer.getRecentEvents()
        let events2 = eventBuffer.getRecentEvents()
        let events3 = eventBuffer.getRecentEvents()

        // Then - should return same events each time (non-destructive read)
        XCTAssertEqual(events1.count, 1)
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events3.count, 1)
    }

    func testBufferPreservesEventProperties() async throws {
        // Given
        let properties = ["key1": "value1", "key2": 123] as [String: Any]
        let event = Event(name: .customEvent("test"), properties: properties)

        // When
        eventBuffer.buffer(event)

        // Wait for async buffer operation to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        let retrievedEvents = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(retrievedEvents.count, 1)
        let retrievedEvent = retrievedEvents.first!
        XCTAssertEqual(retrievedEvent.metric.name.value, "test")
        XCTAssertEqual(retrievedEvent.properties["key1"] as? String, "value1")
        XCTAssertEqual(retrievedEvent.properties["key2"] as? Int, 123)
    }

    func testBufferWithOpenedPushEvent() async throws {
        // Given - simulate real use case
        let pushProperties = ["message_id": "abc123", "campaign_id": "xyz789"] as [String: Any]
        let openedPushEvent = Event(name: ._openedPush, properties: pushProperties)

        // When
        eventBuffer.buffer(openedPushEvent)

        // Wait for async buffer operation to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.metric.name.value, "$opened_push")
        XCTAssertEqual(events.first?.properties["message_id"] as? String, "abc123")
    }
}
