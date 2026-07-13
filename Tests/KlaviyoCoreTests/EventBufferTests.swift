//
//  EventBufferTests.swift
//  klaviyo-swift-sdk
//
//  Created by Ajay Subramanya on 10/7/25.
//

@testable import KlaviyoCore
import Foundation
import XCTest

class EventBufferTests: XCTestCase {
    var eventBuffer: EventBuffer!

    override func setUp() {
        super.setUp()
        // Small limits for testing. The clock is frozen at 0 so events can never age out
        // mid-test on a slow CI runner; tests that exercise age-based behavior build their
        // own buffer via makeClockedBuffer(currentTime:) and advance the clock explicitly.
        eventBuffer = EventBuffer(maxBufferSize: 5, maxBufferAge: 2.0, clock: { 0 })
    }

    override func tearDown() {
        eventBuffer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A buffer whose clock the test controls, so age-based behavior is deterministic
    /// without sleeping real time. `buffer(_:)` is an async barrier write, so callers
    /// must `getRecentEvents()` (a synchronous, barrier-flushing read) to pin an event's
    /// timestamp at the current `currentTime` before advancing the clock.
    private func makeClockedBuffer(
        maxBufferSize: Int = 5,
        maxBufferAge: TimeInterval = 2.0,
        currentTime: @escaping () -> TimeInterval
    ) -> EventBuffer {
        EventBuffer(maxBufferSize: maxBufferSize, maxBufferAge: maxBufferAge, clock: currentTime)
    }

    // MARK: - Basic Functionality Tests

    func testBufferStartsEmpty() {
        // When
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertTrue(events.isEmpty, "Buffer should start empty")
    }

    func testBufferStoresEvent() {
        // Given
        let event = Event(name: .customEvent("test_event"))

        // When — getRecentEvents() is a synchronous, barrier-flushing read, so it observes
        // the preceding async buffer() write deterministically (no sleep needed).
        eventBuffer.buffer(event)
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.metric.name.value, "test_event")
    }

    func testBufferStoresMultipleEvents() {
        // Given
        let event1 = Event(name: .customEvent("event_1"))
        let event2 = Event(name: .customEvent("event_2"))
        let event3 = Event(name: .customEvent("event_3"))

        // When
        eventBuffer.buffer(event1)
        eventBuffer.buffer(event2)
        eventBuffer.buffer(event3)
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].metric.name.value, "event_1")
        XCTAssertEqual(events[1].metric.name.value, "event_2")
        XCTAssertEqual(events[2].metric.name.value, "event_3")
    }

    // MARK: - Buffer Size Limit Tests

    func testBufferRespectsMaxSize() {
        // Given - buffer with maxSize of 5
        let events = (1...7).map { Event(name: .customEvent("event_\($0)")) }

        // When - buffer 7 events
        events.forEach { eventBuffer.buffer($0) }
        let recentEvents = eventBuffer.getRecentEvents()

        // Then - should only keep last 5
        XCTAssertEqual(recentEvents.count, 5, "Buffer should only keep last 5 events")
        XCTAssertEqual(recentEvents[0].metric.name.value, "event_3", "Should drop oldest events")
        XCTAssertEqual(recentEvents[4].metric.name.value, "event_7", "Should keep newest events")
    }

    func testBufferDropsOldestEventsWhenFull() {
        // Given
        eventBuffer.buffer(Event(name: .customEvent("old_event")))

        // When - fill buffer to capacity
        for iter in 1...5 {
            eventBuffer.buffer(Event(name: .customEvent("event_\(iter)")))
        }
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 5)
        XCTAssertFalse(events.contains { $0.metric.name.value == "old_event" }, "Old event should be dropped")
        XCTAssertTrue(events.contains { $0.metric.name.value == "event_5" }, "New events should be kept")
    }

    // MARK: - Buffer Age Limit Tests

    func testBufferFiltersOldEvents() {
        // Given - a buffer with a 2s age limit and a test-controlled clock
        var clock: TimeInterval = 0
        let buffer = makeClockedBuffer(currentTime: { clock })
        buffer.buffer(Event(name: .customEvent("old_event")))
        _ = buffer.getRecentEvents() // flush: pins old_event's timestamp at t=0

        // When - advance the clock past the age limit, then buffer a new event
        clock = 3.0
        buffer.buffer(Event(name: .customEvent("new_event")))
        let events = buffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1, "Should only return the recent event")
        XCTAssertEqual(events.first?.metric.name.value, "new_event")
    }

    func testBufferKeepsRecentEvents() {
        // Given
        var clock: TimeInterval = 0
        let buffer = makeClockedBuffer(currentTime: { clock })
        buffer.buffer(Event(name: .customEvent("recent_event")))
        _ = buffer.getRecentEvents() // flush: pins recent_event's timestamp at t=0

        // When - advance less than the age limit
        clock = 0.5
        let events = buffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1, "Recent event should still be in buffer")
        XCTAssertEqual(events.first?.metric.name.value, "recent_event")
    }

    func testBufferMixesOldAndNewEvents() {
        // Given
        var clock: TimeInterval = 0
        let buffer = makeClockedBuffer(currentTime: { clock })
        buffer.buffer(Event(name: .customEvent("old_event")))
        _ = buffer.getRecentEvents() // flush: pins old_event's timestamp at t=0

        // When - advance past the age limit, then buffer two new events
        clock = 3.0
        buffer.buffer(Event(name: .customEvent("new_event_1")))
        buffer.buffer(Event(name: .customEvent("new_event_2")))
        let events = buffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 2, "Should only return the recent events")
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
            for iter in 0..<50 {
                self.eventBuffer.buffer(Event(name: .customEvent("event_\(iter)")))
            }
            writeExpectation.fulfill()
        }

        DispatchQueue.global().async {
            for _ in 0..<50 {
                _ = self.eventBuffer.getRecentEvents()
            }
            readExpectation.fulfill()
        }

        // Then - should not crash
        await fulfillment(of: [writeExpectation, readExpectation], timeout: 10.0)
        XCTAssertNoThrow(eventBuffer.getRecentEvents())
    }

    // MARK: - Edge Cases

    func testBufferWithZeroMaxSize() {
        // Given
        let zeroBuffer = EventBuffer(maxBufferSize: 0, maxBufferAge: 10.0)

        // When
        zeroBuffer.buffer(Event(name: .customEvent("event")))
        let events = zeroBuffer.getRecentEvents()

        // Then
        XCTAssertTrue(events.isEmpty, "Buffer with size 0 should not store events")
    }

    func testBufferWithZeroMaxAge() {
        // Given
        let zeroAgeBuffer = EventBuffer(maxBufferSize: 10, maxBufferAge: 0.0)

        // When
        zeroAgeBuffer.buffer(Event(name: .customEvent("event")))
        let events = zeroAgeBuffer.getRecentEvents()

        // Then
        XCTAssertTrue(events.isEmpty, "Buffer with age 0 should immediately expire events")
    }

    func testGetRecentEventsMultipleTimes() {
        // Given
        eventBuffer.buffer(Event(name: .customEvent("event")))

        // When
        let events1 = eventBuffer.getRecentEvents()
        let events2 = eventBuffer.getRecentEvents()
        let events3 = eventBuffer.getRecentEvents()

        // Then - should return same events each time (non-destructive read)
        XCTAssertEqual(events1.count, 1)
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events3.count, 1)
    }

    func testBufferPreservesEventProperties() {
        // Given
        let properties = ["key1": "value1", "key2": 123] as [String: Any]
        let event = Event(name: .customEvent("test"), properties: properties)

        // When
        eventBuffer.buffer(event)
        let retrievedEvents = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(retrievedEvents.count, 1)
        let retrievedEvent = retrievedEvents.first!
        XCTAssertEqual(retrievedEvent.metric.name.value, "test")
        XCTAssertEqual(retrievedEvent.properties["key1"] as? String, "value1")
        XCTAssertEqual(retrievedEvent.properties["key2"] as? Int, 123)
    }

    func testBufferWithOpenedPushEvent() {
        // Given - simulate real use case
        let pushProperties = ["message_id": "abc123", "campaign_id": "xyz789"] as [String: Any]
        let openedPushEvent = Event(name: ._openedPush, properties: pushProperties)

        // When
        eventBuffer.buffer(openedPushEvent)
        let events = eventBuffer.getRecentEvents()

        // Then
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.metric.name.value, "$opened_push")
        XCTAssertEqual(events.first?.properties["message_id"] as? String, "abc123")
    }
}
