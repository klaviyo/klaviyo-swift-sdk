@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

final class RequestEnqueuerPreInitGateTests: KlaviyoBaseTestCase {
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        LifecycleState.shared.reset()
        PreInitMemoryBuffer.shared.reset()
        resetCanonicalCoreStores() // no apiKey in SDKConfigStore → pre-init routing
    }

    // priority: .high requires the package init — the public init always sets .standard.
    private var openedPush: Event { Event(name: ._openedPush, priority: .high) }

    /// Parity (capture OFF): a regular pre-init event is DROPPED — no disk buffer, no queue.
    @MainActor
    func testParityRegularPreInitEventIsDropped() {
        featureFlags.enablePreInitDiskCapture = false
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))

        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("Added to Cart")))

        XCTAssertTrue(UnattributedBuffer.shared.drainSnapshot().requests.isEmpty,
                      "parity: regular pre-init event must not hit the durable buffer")
        XCTAssertTrue(PreInitMemoryBuffer.shared.drain().isEmpty,
                      "parity: regular event is not a push-open → dropped, not held in memory")
    }

    /// Parity (capture OFF): a pre-init push-open (.high) is held in the in-memory buffer, NOT disk.
    @MainActor
    func testParityPreInitPushOpenHeldInMemoryOnly() {
        featureFlags.enablePreInitDiskCapture = false
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))

        RequestEnqueuer.enqueueEvent(openedPush)

        XCTAssertTrue(UnattributedBuffer.shared.drainSnapshot().requests.isEmpty,
                      "parity: push-open must not be persisted to disk")
        XCTAssertEqual(PreInitMemoryBuffer.shared.drain().count, 1,
                       "parity: pre-init push-open must be held in the non-durable memory buffer")
    }

    /// Parity: drainBuffer at init moves the in-memory push-open into QueueStore.
    @MainActor
    func testParityDrainMovesMemoryPushOpenToQueue() {
        featureFlags.enablePreInitDiskCapture = false
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))
        RequestEnqueuer.enqueueEvent(openedPush)
        // Now an apiKey arrives; drain into the queue.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        let readQueue = seedTestQueueStore()

        RequestEnqueuer.drainBuffer(apiKey: TEST_API_KEY)

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "the buffered push-open must be enqueued at drain")
        guard case .createEvent = queued.first?.endpoint else {
            return XCTFail("expected createEvent, got \(queued.first?.endpoint as Any)")
        }
    }

    /// Capture ON: all pre-init calls land in the durable UnattributedBuffer (current behavior).
    @MainActor
    func testCaptureOnBuffersRegularEventToDisk() {
        featureFlags.enablePreInitDiskCapture = true
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))

        RequestEnqueuer.enqueueEvent(Event(name: .customEvent("Added to Cart")))

        XCTAssertEqual(UnattributedBuffer.shared.drainSnapshot().requests.count, 1,
                       "capture ON: regular pre-init event must be durably buffered")
        XCTAssertTrue(PreInitMemoryBuffer.shared.drain().isEmpty)
    }
}
