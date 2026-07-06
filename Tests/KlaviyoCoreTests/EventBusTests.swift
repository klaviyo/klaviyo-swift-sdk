//
//  EventBusTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Combine
import XCTest

final class EventBusTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        super.tearDown()
    }

    // Live delivery: a subscriber receives events published after it subscribes.
    func testPublishDeliversToLiveSubscriber() {
        let bus = EventBus()
        let expectation = XCTestExpectation(description: "event received")
        var received: Event?

        bus.eventPublisher()
            .sink { received = $0; expectation.fulfill() }
            .store(in: &cancellables)

        bus.publish(Event(name: .customEvent("live_event")))

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received?.metric.name.value, "live_event")
    }

    // Race fix: events published BEFORE a subscriber attaches are replayed, in order, then live.
    func testReplaysBufferedEventsBeforeSubscribeThenLive() {
        let bus = EventBus()

        bus.publish(Event(name: .customEvent("before_1")))
        bus.publish(Event(name: .customEvent("before_2")))

        let expectation = XCTestExpectation(description: "three events, replay then live")
        expectation.expectedFulfillmentCount = 3
        var names: [String] = []

        bus.eventPublisher()
            .sink { names.append($0.metric.name.value); expectation.fulfill() }
            .store(in: &cancellables)

        bus.publish(Event(name: .customEvent("after_live")))

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(names, ["before_1", "before_2", "after_live"])
    }

    // Buffer bound: only the last `maxBufferSize` events are replayed.
    func testReplayRespectsMaxBufferSize() {
        let bus = EventBus(buffer: EventBuffer(maxBufferSize: 2, maxBufferAge: 10))

        bus.publish(Event(name: .customEvent("e1")))
        bus.publish(Event(name: .customEvent("e2")))
        bus.publish(Event(name: .customEvent("e3")))

        let expectation = XCTestExpectation(description: "only last 2 replayed")
        expectation.expectedFulfillmentCount = 2
        var names: [String] = []

        bus.eventPublisher()
            .sink { names.append($0.metric.name.value); expectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(names, ["e2", "e3"])
    }
}
