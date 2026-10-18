@testable import KlaviyoCore
import Combine
import XCTest

final class EventRecoveryTests: XCTestCase {
    func testOriginValidityUsesStrictOriginalAgeAndOptionalAgeCheck() {
        var time: TimeInterval = 100
        let eventBus = EventBus(buffer: EventBuffer(clock: { time }))
        let origin = eventBus.captureOrigin(apiKey: "company", identity: ProfileData(anonymousId: "anon"))
        XCTAssertTrue(eventBus.isCurrent(origin, within: 10))
        XCTAssertFalse(eventBus.isCurrent(origin, within: 0))
        time = 109.999
        XCTAssertTrue(eventBus.isCurrent(origin, within: 10))
        time = 110
        XCTAssertFalse(eventBus.isCurrent(origin, within: 10))
        XCTAssertTrue(eventBus.isCurrent(origin))
        time = 130
        XCTAssertFalse(eventBus.isCurrent(origin, within: 30))
    }

    func testOriginValidityPreservesCompatibleContextAndRejectsReplacementCompanyAndReset() {
        let eventBus = EventBus()
        let anonymous = ProfileData(anonymousId: "anon")
        let origin = eventBus.captureOrigin(apiKey: "company", identity: anonymous)
        eventBus.updateContext(
            apiKey: "company", identity: ProfileData(email: "a@example.com", anonymousId: "anon")
        )
        XCTAssertTrue(eventBus.isCurrent(origin))
        eventBus.updateContext(apiKey: "company", identity: ProfileData(
            email: "a@example.com", externalId: "id", anonymousId: "anon"
        ))
        XCTAssertTrue(eventBus.isCurrent(origin))
        eventBus.updateContext(
            apiKey: "company", identity: ProfileData(email: "b@example.com", anonymousId: "anon")
        )
        XCTAssertFalse(eventBus.isCurrent(origin))
        let replacement = eventBus.captureOrigin(apiKey: "company", identity: anonymous)
        eventBus.updateContext(apiKey: "other", identity: anonymous)
        XCTAssertFalse(eventBus.isCurrent(replacement))
        let otherCompany = eventBus.captureOrigin(apiKey: "other", identity: anonymous)
        eventBus.reset()
        XCTAssertFalse(eventBus.isCurrent(otherCompany))
    }

    func testReplayUsesOriginalMonotonicArrivalAndStrictConfiguredWindow() {
        var currentTime: TimeInterval = 0
        let buffer = EventBuffer(maxBufferAge: 30, clock: { currentTime })
        buffer.buffer(Event(name: .customEvent("old")))
        _ = buffer.getRecentEvents()
        currentTime = 10
        XCTAssertTrue(buffer.getRecentEvents().isEmpty)
        XCTAssertEqual(buffer.getRecentEvents(maxAge: 30).count, 1)
        XCTAssertTrue(buffer.getRecentEvents(maxAge: 0).isEmpty)
        currentTime = 30
        XCTAssertTrue(buffer.getRecentEvents(maxAge: 30).isEmpty)
    }

    func testReplayHandoffIncludesReentrantLiveEventsExactlyOnceInOrder() {
        let eventBus = EventBus()
        eventBus.publish(Event(name: .customEvent("first")))
        eventBus.publish(Event(name: .customEvent("second")))
        var names: [String] = []
        let subscription = eventBus.eventPublisher().sink { event in
            names.append(event.metric.name.value)
            if names.count == 1 { eventBus.publish(Event(name: .customEvent("during-replay"))) }
        }
        XCTAssertEqual(names, ["first", "second", "during-replay"])
        withExtendedLifetime(subscription) {}
    }

    func testDeferredPublicationDoesNotRefreshArrivalAge() {
        var currentTime: TimeInterval = 0
        let eventBus = EventBus(buffer: EventBuffer(clock: { currentTime }))
        let origin = eventBus.captureOrigin(apiKey: "company", identity: ProfileData(anonymousId: "anon"))
        currentTime = 10
        eventBus.publish(Event(name: .customEvent("deferred")), origin: origin)
        var events: [Event] = []
        let subscription = eventBus.eventPublisher().sink { events.append($0) }
        XCTAssertTrue(events.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    func testExpiredDeferredEventDoesNotDisplaceRecentHistory() {
        let buffer = EventBuffer(maxBufferSize: 2, clock: { 31 })
        buffer.buffer(Event(name: .customEvent("recent-first")))
        buffer.buffer(Event(name: .customEvent("recent-second")))
        buffer.buffer(Event(name: .customEvent("expired")), arrivedAt: 0)
        XCTAssertEqual(
            buffer.getRecentEvents().map(\.metric.name.value), ["recent-first", "recent-second"]
        )
    }

    func testReplayPreservesIDTimeOrderAndNestedCopyIsolation() {
        let nested = NSMutableDictionary(dictionary: ["color": "blue"])
        let buffer = EventBuffer(clock: { 0 })
        let timestamp = Date(timeIntervalSince1970: 123)
        buffer.buffer(Event(
            name: .customEvent("first"),
            properties: ["nested": nested],
            time: timestamp,
            uniqueId: "id-1"
        ))
        nested["color"] = "red"
        let firstRead = buffer.getRecentEvents()
        XCTAssertEqual(firstRead.first?.uniqueId, "id-1")
        XCTAssertEqual(firstRead.first?.time, timestamp)
        XCTAssertEqual((firstRead.first?.properties["nested"] as? [String: String])?["color"], "blue")
        var properties = firstRead[0].properties
        properties["nested"] = ["color": "green"]
        XCTAssertEqual(
            (buffer.getRecentEvents()[0].properties["nested"] as? [String: String])?["color"],
            "blue"
        )
    }

    func testZeroReplayKeepsLiveDeliveryAndCapacityIsTen() {
        let eventBus = EventBus()
        for index in 0..<12 {
            eventBus.publish(Event(name: .customEvent("event-\(index)")))
        }
        var names: [String] = []
        let live = eventBus.formEventPublisher(replayWindow: 0)
            .sink { names.append($0.event.metric.name.value) }
        XCTAssertTrue(names.isEmpty)
        eventBus.publish(Event(name: .customEvent("live")))
        XCTAssertEqual(names, ["live"])
        var replayed: [Event] = []
        let replay = eventBus.eventPublisher().sink { replayed.append($0) }
        XCTAssertEqual(replayed.count, 10)
        XCTAssertEqual(replayed.first?.metric.name.value, "event-3")
        withExtendedLifetime((live, replay)) {}
    }

    func testOriginFenceRejectsDeferredPublicationAndQueuedDelivery() {
        let eventBus = EventBus()
        let original = ProfileData(email: "a@example.com", anonymousId: "anon")
        let origin = eventBus.captureOrigin(apiKey: "first", identity: original)
        var deliveries: [EventBus.Delivery] = []
        let subscription = eventBus.formEventPublisher(replayWindow: 30).sink { deliveries.append($0) }
        eventBus.publish(Event(name: .customEvent("queued")), origin: origin)
        eventBus.updateContext(apiKey: "second", identity: original)
        XCTAssertFalse(eventBus.isCurrent(deliveries[0]))
        eventBus.publish(Event(name: .customEvent("deferred")), origin: origin)
        XCTAssertEqual(deliveries.count, 1)
        var replay: [Event] = []
        let replaySubscription = eventBus.eventPublisher().sink { replay.append($0) }
        XCTAssertTrue(replay.isEmpty)
        withExtendedLifetime((subscription, replaySubscription)) {}
    }

    func testAnonymousIdentificationAndCompatibleEnrichmentKeepHistoryButReplacementClearsIt() {
        let eventBus = EventBus()
        eventBus.updateContext(apiKey: "company", identity: ProfileData(anonymousId: "anon"))
        eventBus.publish(Event(name: .customEvent("anonymous")))
        eventBus.updateContext(
            apiKey: "company",
            identity: ProfileData(email: "a@example.com", anonymousId: "anon")
        )
        eventBus.updateContext(
            apiKey: "company",
            identity: ProfileData(email: "a@example.com", externalId: "id", anonymousId: "anon")
        )
        var names: [String] = []
        let first = eventBus.eventPublisher().sink { names.append($0.metric.name.value) }
        XCTAssertEqual(names, ["anonymous"])
        eventBus.updateContext(
            apiKey: "company",
            identity: ProfileData(email: "b@example.com", anonymousId: "anon")
        )
        var replacement: [Event] = []
        let second = eventBus.eventPublisher().sink { replacement.append($0) }
        XCTAssertTrue(replacement.isEmpty)
        withExtendedLifetime((first, second)) {}
    }
}
