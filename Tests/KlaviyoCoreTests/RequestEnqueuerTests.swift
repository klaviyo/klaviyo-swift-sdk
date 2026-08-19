//
//  RequestEnqueuerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/26.
//

@testable import KlaviyoCore
import XCTest

final class RequestEnqueuerTests: XCTestCase {
    private var fileIO: FileIODouble!

    override func setUp() {
        super.setUp()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
        UnattributedBuffer.shared.reset()
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetRegistry()
    }

    override func tearDown() {
        UnattributedBuffer.shared.reset()
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetRegistry()
        environment = KlaviyoEnvironment.test()
        fileIO = nil
        super.tearDown()
    }

    // MARK: - enqueueEvent

    func testEventWithoutApiKeyGoesToBuffer() {
        // no apiKey set
        // IdentityStore mints anonymousId on first access (MAGE-894 single minter), so it is always
        // non-nil here — the anonymousId guard in RequestEnqueuer is defensive, never reached.
        XCTAssertNotNil(IdentityStore.shared.current.anonymousId)
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("X")))
        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case .event = snap[0] else { return XCTFail("expected .event in buffer") }
        XCTAssertNil(QueueStore.current()) // no queue exists pre-apiKey
    }

    func testEventWithApiKeyGoesToQueueStore() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("X")))
        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        XCTAssertEqual(QueueStore.current()?.count, 1)
    }

    func testPriorityEventFrontInsertsInQueue() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("normal")))
        RequestEnqueuer.enqueueEvent(
            Event(name: .customEvent("urgent"), properties: nil, identifiers: nil,
                  value: nil, priority: .high))
        let requests = QueueStore.current()!.requests
        XCTAssertEqual(requests.first?.priority, .high)
    }

    func testHighPriorityEventInBufferStoresHighPriority() {
        // no apiKey set — event goes to UnattributedBuffer; assert the priority is preserved
        RequestEnqueuer.enqueueEvent(
            Event(name: .customEvent("urgent"), properties: nil, identifiers: nil,
                  value: nil, priority: .high))
        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case let .event(_, priority) = snap[0] else {
            return XCTFail("expected .event in buffer")
        }
        XCTAssertEqual(priority, .high)
    }

    // MARK: - enqueueProfile

    func testProfileWithoutApiKeyBuffersProfilePayload() {
        RequestEnqueuer.enqueueProfile(properties: ["k": "v"])
        guard case .profile = UnattributedBuffer.shared.snapshot().first else {
            return XCTFail("expected .profile in buffer")
        }
    }

    // MARK: - enqueueAggregateEvent

    func testAggregateEventWithoutApiKeyGoesToBuffer() {
        let payload = Data("test-aggregate".utf8)
        RequestEnqueuer.enqueueAggregateEvent(payload)
        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case let .aggregateEvent(bufferedPayload) = snap[0] else {
            return XCTFail("expected .aggregateEvent in buffer")
        }
        XCTAssertEqual(bufferedPayload, payload)
        XCTAssertNil(QueueStore.current())
    }

    func testAggregateEventWithApiKeyGoesToQueueStore() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        let payload = Data("test-aggregate".utf8)
        RequestEnqueuer.enqueueAggregateEvent(payload)
        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        XCTAssertEqual(QueueStore.current()?.count, 1)
        let request = QueueStore.current()?.requests.first
        guard case .aggregateEvent = request?.endpoint else {
            return XCTFail("expected .aggregateEvent endpoint in QueueStore")
        }
    }

    // MARK: - enqueuePushToken

    func testPushTokenWithoutApiKeyGoesToBuffer() {
        RequestEnqueuer.enqueuePushToken("device-token-abc", enablement: .authorized)
        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case .pushToken = snap[0] else {
            return XCTFail("expected .pushToken in buffer")
        }
        XCTAssertNil(QueueStore.current())
    }

    func testPushTokenWithApiKeyGoesToQueueStore() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.enqueuePushToken("device-token-abc", enablement: .authorized)
        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        XCTAssertEqual(QueueStore.current()?.count, 1)
        let request = QueueStore.current()?.requests.first
        guard case .registerPushToken = request?.endpoint else {
            return XCTFail("expected .registerPushToken endpoint in QueueStore")
        }
    }
}
