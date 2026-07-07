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

        XCTAssertEqual(spy.received.count, 2)
        guard case let .aggregateEvent(received) = spy.received[0], received == payload else {
            return XCTFail("expected .aggregateEvent(payload)")
        }
        guard case let .deepLink(received) = spy.received[1], received == url else {
            return XCTFail("expected .deepLink(url)")
        }
    }

    func testDispatchWithoutRegistrationWarnsAndDoesNotForward() {
        let dispatcher = EventDispatcher()
        var warnings: [String] = []
        environment.emitDeveloperWarning = { warnings.append($0) }

        dispatcher.dispatch(.deepLink(URL(string: "https://example.com")!))

        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("dispatch before registration"))
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
}
