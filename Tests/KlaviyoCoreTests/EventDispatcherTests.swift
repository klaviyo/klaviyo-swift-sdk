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

    func testDispatchForwardsToRegisteredTarget() throws {
        let dispatcher = EventDispatcher()
        let spy = SpyDispatcher()
        dispatcher.register(spy)

        let payload = Data("agg".utf8)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
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

    func testDispatchWithoutRegistrationWarnsAndDoesNotForward() throws {
        let dispatcher = EventDispatcher()
        let spy = SpyDispatcher() // created but intentionally NOT registered
        var warnings: [String] = []
        environment.emitDeveloperWarning = { warnings.append($0) }

        try dispatcher.dispatch(.deepLink(XCTUnwrap(URL(string: "https://example.com"))))

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

    // Thread-safe spy for the concurrency test: `dispatch` may be called from many threads at once,
    // so its own bookkeeping must be synchronized independently of the code under test.
    private final class CountingDispatcher: EventDispatching {
        private let lock = UnfairLock()
        private var _count = 0
        var count: Int { lock.withLock { _count } }
        func dispatch(_: InboundCommand) { lock.withLock { _count += 1 } }
    }

    // Stress concurrent register/dispatch/reset. Exercises the snapshot-under-lock-then-forward-
    // outside path and the register/dispatch race on `target`. Success = no crash, no deadlock, and
    // every dispatch either forwards to the currently-registered target or hits the warning path
    // (never both, never a torn read). Meaningful under Thread Sanitizer.
    func testConcurrentRegisterDispatchResetDoesNotRace() {
        let dispatcher = EventDispatcher()
        let target = CountingDispatcher()
        environment.emitDeveloperWarning = { _ in } // may fire when dispatch races a reset; ignore
        dispatcher.register(target)

        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            switch index % 4 {
            case 0: dispatcher.register(target)
            case 1: dispatcher.reset()
            default: dispatcher.dispatch(.aggregateEvent(Data()))
            }
        }

        // Leave a deterministic final state: re-register and confirm forwarding still works.
        dispatcher.register(target)
        let before = target.count
        dispatcher.dispatch(.aggregateEvent(Data()))
        XCTAssertEqual(target.count, before + 1)
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
