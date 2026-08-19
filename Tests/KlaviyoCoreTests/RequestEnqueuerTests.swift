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

    func testEventWithoutApiKeyGoesToBuffer() {
        // no apiKey set
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

    func testProfileWithoutApiKeyBuffersProfilePayload() {
        RequestEnqueuer.enqueueProfile(properties: ["k": "v"])
        guard case .profile = UnattributedBuffer.shared.snapshot().first else {
            return XCTFail("expected .profile in buffer")
        }
    }
}
