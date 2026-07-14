//
//  EventDispatcherTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import Foundation
import XCTest

final class EventDispatcherTests: XCTestCase {
    private final class SpyDispatcher: EventDispatching {
        private(set) var received: [InboundCommand] = []
        func dispatch(_ command: InboundCommand) { received.append(command) }
    }

    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

    func testDispatchForwardsToRegisteredTarget() {
        let dispatcher = EventDispatcher()
        let spy = SpyDispatcher()
        dispatcher.register(spy)

        let payload = Data("agg".utf8)
        let url = URL(string: "https://example.com")!
        dispatcher.dispatch(.aggregateEvent(payload))
        dispatcher.dispatch(.deepLink(url))

        guard spy.received.count == 2 else {
            return XCTFail("expected 2 commands, got \(spy.received.count)")
        }
        guard case let .aggregateEvent(received) = spy.received[0], received == payload else {
            return XCTFail("expected .aggregateEvent(payload)")
        }
        guard case let .deepLink(received) = spy.received[1], received == url else {
            return XCTFail("expected .deepLink(url)")
        }
    }

    func testDispatchForwardsCreateEvent() {
        let dispatcher = EventDispatcher()
        let spyDispatcher = SpyDispatcher()
        dispatcher.register(spyDispatcher)

        let event = Event(name: .customEvent("Viewed Product"), properties: ["foo": "bar"])
        dispatcher.dispatch(.createEvent(event))

        guard spyDispatcher.received.count == 1 else {
            return XCTFail("expected 1 command, got \(spyDispatcher.received.count)")
        }
        guard case let .createEvent(received) = spyDispatcher.received[0] else {
            return XCTFail("expected .createEvent")
        }
        XCTAssertEqual(received.metric.name, .customEvent("Viewed Product"))
        XCTAssertEqual(received.properties["foo"] as? String, "bar")
    }

    func testDispatchWithoutRegistrationWarnsAndDoesNotForward() {
        let dispatcher = EventDispatcher()
        let spy = SpyDispatcher() // created but intentionally NOT registered
        var warnings: [String] = []
        environment.emitDeveloperWarning = { warnings.append($0) }

        dispatcher.dispatch(.deepLink(URL(string: "https://example.com")!))

        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("dispatch before registration"))
        XCTAssertTrue(spy.received.isEmpty)
    }

    func testReRegisterReplacesTarget() {
        let dispatcher = EventDispatcher()
        let first = SpyDispatcher()
        let second = SpyDispatcher()
        dispatcher.register(first)
        dispatcher.register(second)

        dispatcher.dispatch(.aggregateEvent(Data()))

        XCTAssertTrue(first.received.isEmpty)
        XCTAssertEqual(second.received.count, 1)
    }

    // reset(): after reset(), dispatch should warn and not forward to the previous target.
    func testResetUnregistersTarget() {
        let dispatcher = EventDispatcher()
        let spyDispatcher = SpyDispatcher()
        dispatcher.register(spyDispatcher)

        dispatcher.reset()

        var warnings: [String] = []
        environment.emitDeveloperWarning = { warnings.append($0) }
        dispatcher.dispatch(.aggregateEvent(Data()))

        XCTAssertTrue(spyDispatcher.received.isEmpty) // no forward after reset
        XCTAssertEqual(warnings.count, 1) // hits the unregistered path
        XCTAssertTrue(warnings[0].contains("dispatch before registration"))
    }
}
