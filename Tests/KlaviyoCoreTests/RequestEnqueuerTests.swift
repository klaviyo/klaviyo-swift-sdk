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

    /// Shared fixture: a tracking link whose destination fails to resolve before initialize().
    private let trackingLinkURL = URL(string: "https://klaviyo.com/tracking/abc")!

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

    func testProfileWithoutApiKeyBuffersFullPayload() {
        // The caller supplies a fully-built payload, so structured attributes survive into the
        // durable buffer (MAGE-1141).
        let payload = CreateProfilePayload(data: ProfilePayload(
            email: "ada@example.com", firstName: "Ada", anonymousId: "anon-1"
        ))
        RequestEnqueuer.enqueueProfile(payload: payload)

        guard case let .profile(buffered) = UnattributedBuffer.shared.snapshot().first else {
            return XCTFail("expected .profile in buffer")
        }
        XCTAssertEqual(buffered.data.attributes.firstName, "Ada")
        XCTAssertNil(QueueStore.current()) // no queue exists pre-apiKey
    }

    func testProfileWithApiKeyGoesToQueueStore() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        let payload = CreateProfilePayload(data: ProfilePayload(
            email: "ada@example.com", anonymousId: "anon-1"
        ))
        RequestEnqueuer.enqueueProfile(payload: payload)

        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        XCTAssertEqual(QueueStore.current()?.count, 1)
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

    func testRepeatedPushTokenWithoutApiKeyCoalescesToLatest() {
        // Models repeated pre-init fires (e.g. multiple automatic APNs callbacks before
        // `initialize()`) — only the latest token should survive in the buffer, not one entry
        // per fire, so drain doesn't send N redundant register calls (MAGE-1137).
        RequestEnqueuer.enqueuePushToken("token-1", enablement: .authorized)
        RequestEnqueuer.enqueuePushToken("token-2", enablement: .authorized)
        RequestEnqueuer.enqueuePushToken("token-3", enablement: .authorized)

        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case let .pushToken(payload) = snap[0] else {
            return XCTFail("expected .pushToken in buffer")
        }
        XCTAssertEqual(payload.data.attributes.token, "token-3")
    }

    // MARK: - enqueueSubscription

    private func subscriptionPayload(email: String = "a@b.com") -> CreateSubscriptionPayload {
        CreateSubscriptionPayload(
            listId: "list-1",
            profile: ProfilePayload(email: email, anonymousId: "anon-1"),
            customSource: nil
        )
    }

    func testSubscriptionWithoutApiKeyGoesToBuffer() {
        RequestEnqueuer.enqueueSubscription(payload: subscriptionPayload())
        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case .subscription = snap[0] else { return XCTFail("expected .subscription in buffer") }
        XCTAssertNil(QueueStore.current())
    }

    func testSubscriptionWithApiKeyGoesToQueueStore() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.enqueueSubscription(payload: subscriptionPayload())
        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        XCTAssertEqual(QueueStore.current()?.count, 1)
        guard case .createSubscription = QueueStore.current()?.requests.first?.endpoint else {
            return XCTFail("expected .createSubscription endpoint in QueueStore")
        }
    }

    func testDrainMapsSubscriptionToCreateSubscriptionEndpoint() {
        RequestEnqueuer.enqueueSubscription(payload: subscriptionPayload())
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.drainBuffer(apiKey: "pk-1")

        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        guard case let .createSubscription(apiKey, _) =
            QueueStore.current()?.requests.first?.endpoint
        else {
            return XCTFail("expected .createSubscription endpoint after drain")
        }
        XCTAssertEqual(apiKey, "pk-1", "apiKey is stamped at drain")
    }

    // MARK: - enqueueTrackingLinkClicked

    func testTrackingLinkClickWithoutApiKeyGoesToBuffer() {
        // A universal-link click that fails destination resolution before initialize() must park
        // its click-log in the durable buffer instead of being dropped (MAGE-1136).
        RequestEnqueuer.enqueueTrackingLinkClicked(
            trackingLink: trackingLinkURL, clickTime: environment.date()
        )
        let snap = UnattributedBuffer.shared.snapshot()
        XCTAssertEqual(snap.count, 1)
        guard case let .trackingLinkClick(trackingLink, _, _) = snap[0] else {
            return XCTFail("expected .trackingLinkClick in buffer")
        }
        XCTAssertEqual(trackingLink, trackingLinkURL)
        XCTAssertNil(QueueStore.current())
    }

    func testTrackingLinkClickWithApiKeyGoesToQueueStore() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.enqueueTrackingLinkClicked(
            trackingLink: trackingLinkURL, clickTime: environment.date()
        )
        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        XCTAssertEqual(QueueStore.current()?.count, 1)
        guard case .logTrackingLinkClicked = QueueStore.current()?.requests.first?.endpoint else {
            return XCTFail("expected .logTrackingLinkClicked endpoint in QueueStore")
        }
    }

    // MARK: - drainBuffer

    func testDrainMovesBufferedRequestsToQueueInFifoOrder() {
        // Buffer three events with no apiKey.
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("1")))
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("2")))
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("3")))

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.drainBuffer(apiKey: "pk-1")

        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        XCTAssertEqual(QueueStore.current()?.count, 3)
        // Verify FIFO order, not just count: reversing the drain would still pass a count check.
        let names = (QueueStore.current()?.requests ?? []).compactMap { request -> String? in
            guard case let .createEvent(_, payload) = request.endpoint else { return nil }
            return payload.data.attributes.metric.data.attributes.name
        }
        XCTAssertEqual(names, ["1", "2", "3"], "drain must preserve FIFO order")
    }

    func testDrainPreservesPriorityFrontInsert() {
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("normal")))
        RequestEnqueuer.enqueueEvent(
            Event(name: .customEvent("urgent"), properties: nil, identifiers: nil,
                  value: nil, priority: .high))

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.drainBuffer(apiKey: "pk-1")

        XCTAssertEqual(QueueStore.current()?.requests.first?.priority, .high)
    }

    func testDrainMapsTrackingLinkClickToLogEndpoint() {
        RequestEnqueuer.enqueueTrackingLinkClicked(
            trackingLink: trackingLinkURL, clickTime: environment.date()
        )

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.drainBuffer(apiKey: "pk-1")

        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 0)
        guard case let .logTrackingLinkClicked(trackingLink, _, _) =
            QueueStore.current()?.requests.first?.endpoint
        else {
            return XCTFail("expected .logTrackingLinkClicked endpoint after drain")
        }
        XCTAssertEqual(trackingLink, trackingLinkURL)
    }

    func testDrainEmptyBufferIsNoOp() {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.drainBuffer(apiKey: "pk-1")
        XCTAssertEqual(QueueStore.current()?.count, 0)
    }

    func testDrainPersistsQueueBeforeClearingBuffer() {
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("1")))
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        RequestEnqueuer.drainBuffer(apiKey: "pk-1")
        // Buffer file must be gone.
        XCTAssertNil(loadPersisted(PersistedUnattributedBuffer.self, fileName: StoreFile.unattributed))
        // Queue must be durable on disk (synchronous final enqueue).
        let onDisk = loadPersisted(PersistedQueue.self, fileName: "klaviyo-pk-1-queue.json")
        XCTAssertEqual(onDisk?.requests.count, 1)
    }

    func testDrainWithMismatchedApiKeyIsSkipped() {
        // Configure the active SDK key to "pk-1" and buffer one event.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        // Reset to no-apiKey so the event lands in the buffer, then drain with wrong key.
        SDKConfigStore.shared.reset()
        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("buffered")))
        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 1, "pre-condition: event buffered")

        // Set active key back to "pk-1" so QueueStore resolves it, then drain with a wrong key.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-1"))
        var warnings: [String] = []
        environment.emitDeveloperWarning = { warnings.append($0) }

        RequestEnqueuer.drainBuffer(apiKey: "pk-2")

        // Buffer must NOT have been cleared — at-least-once preservation.
        XCTAssertEqual(UnattributedBuffer.shared.snapshot().count, 1,
                       "buffer should be intact when apiKeys mismatch")
        // The pk-1 queue must be empty — no requests written to the wrong queue.
        XCTAssertEqual(QueueStore.current()?.count, 0,
                       "pk-1 QueueStore should be empty after skipped drain")
        XCTAssertFalse(warnings.isEmpty, "a developer warning should have been emitted")
    }
}
