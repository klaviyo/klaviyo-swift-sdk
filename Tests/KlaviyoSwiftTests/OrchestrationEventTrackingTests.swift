//
//  OrchestrationEventTrackingTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/15/26.
//
//  Parity coverage for the event-enqueue and tracking-link reducer cases being ported into
//  `KlaviyoOrchestration` (Task 4c). Reproduces the coverage from `StateManagementTests`
//  (`testEnqueueEvents`, `testPreInitEventRoutesToUnattributedBuffer`, priority/flush tests)
//  and the relevant scenarios from `ResolveTrackingLinkTests` (resolved → openDeepLink,
//  failed → enqueueTrackingLinkClicked, pre-init → UnattributedBuffer).

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import Foundation
import XCTest

class OrchestrationEventTrackingTests: StateManagementTestCase {
    // MARK: - Test lifecycle

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        // LifecycleState is a KlaviyoSwift singleton; reset so each test starts `.uninitialized`.
        LifecycleState.shared.reset()
        EventBus.shared.reset()
        DeepLinkManager.resetToProduction()
    }

    @MainActor
    override func tearDown() async throws {
        DeepLinkManager.resetToProduction()
        EventBus.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Seeds canonical stores and advances LifecycleState to `.initialized`.
    /// Returns a tuple of (apiKey, anonymousId, pushToken).
    @discardableResult
    private func seedPostInit(
        apiKey: String = TEST_API_KEY,
        anonymousId: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        externalId: String? = nil,
        pushToken: String = "blob_token"
    ) -> (apiKey: String, anonymousId: String, pushToken: String) {
        let resolvedAnon = anonymousId ?? environment.uuid().uuidString
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(ProfileData(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            anonymousId: resolvedAnon
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushToken,
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()
        return (apiKey, resolvedAnon, pushToken)
    }

    /// Seeds a pre-init state: anonymousId only, LifecycleState stays `.uninitialized`.
    private func seedPreInit(anonymousId: String? = nil) {
        let resolvedAnon = anonymousId ?? environment.uuid().uuidString
        IdentityStore.shared.update(ProfileData(anonymousId: resolvedAnon))
    }

    /// Seeds an `.initializing` state (between begin and complete).
    private func seedInitializing(anonymousId: String? = nil) {
        let resolvedAnon = anonymousId ?? environment.uuid().uuidString
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: resolvedAnon))
        LifecycleState.shared.beginInitializing()
        // Note: completeInitialization() is intentionally NOT called.
    }

    // MARK: - enqueueEvent: always routes to RequestEnqueuer

    /// Pre-init: event must still land in the durable buffer via `RequestEnqueuer`.
    @MainActor
    func testEnqueueEventPreInitBuffersViaRequestEnqueuer() {
        UnattributedBuffer.shared.reset()
        seedPreInit()

        KlaviyoOrchestration.enqueueEvent(.test)

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1,
                       "pre-init enqueueEvent must buffer the event, not drop it")
    }

    /// Initialized: event must be enqueued into QueueStore via `RequestEnqueuer`.
    @MainActor
    func testEnqueueEventPostInitRoutesToQueueStore() {
        let (apiKey, _, _) = seedPostInit()
        let readQueue = seedTestQueueStore()

        let event = Event(name: .customEvent("test-event"))
        KlaviyoOrchestration.enqueueEvent(event)

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "post-init enqueueEvent must enqueue exactly one event request")
        guard case let .createEvent(queuedApiKey, _) = queued.first?.endpoint else {
            return XCTFail("expected createEvent, got \(queued.first?.endpoint as Any)")
        }
        XCTAssertEqual(queuedApiKey, apiKey)
    }

    // MARK: - enqueueEvent: strict .initialized gate (publish + flush)

    /// Post-init (`.initialized`), high-priority event: must trigger `flushNow()` on the
    /// spy request queue AND publish to `EventBus`.
    @MainActor
    func testEnqueueHighPriorityEventPostInitFlushesAndPublishes() async {
        seedPostInit()
        seedTestQueueStore()
        let spyQueue = installSpyRequestQueue()

        let published = expectation(description: "EventBus publish received")
        var cancellables = Set<AnyCancellable>()
        EventBus.shared.eventPublisher()
            .sink { _ in published.fulfill() }
            .store(in: &cancellables)
        defer { cancellables.forEach { $0.cancel() } }

        KlaviyoOrchestration.enqueueEvent(Event(name: ._openedPush, priority: .high))

        await fulfillment(of: [published], timeout: 2.0)
        let flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 1, "high-priority post-init event must trigger flushNow()")
    }

    /// Post-init (`.initialized`), standard event: must publish to EventBus but NOT flush.
    @MainActor
    func testEnqueueStandardEventPostInitPublishesButNoFlush() async {
        seedPostInit()
        seedTestQueueStore()
        let spyQueue = installSpyRequestQueue()

        let published = expectation(description: "EventBus publish received")
        var cancellables = Set<AnyCancellable>()
        EventBus.shared.eventPublisher()
            .sink { _ in published.fulfill() }
            .store(in: &cancellables)
        defer { cancellables.forEach { $0.cancel() } }

        KlaviyoOrchestration.enqueueEvent(Event(name: .openedAppMetric))

        await fulfillment(of: [published], timeout: 2.0)
        let flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 0, "standard post-init event must NOT trigger flushNow()")
    }

    /// Pre-init (`.uninitialized`): must NOT publish to EventBus and must NOT flush.
    /// Proves the strict `.initialized` gate: pre-init events skip the publish path entirely.
    @MainActor
    func testEnqueueEventPreInitNoPublishNoFlush() async {
        UnattributedBuffer.shared.reset()
        seedPreInit()
        let spyQueue = installSpyRequestQueue()

        let unexpected = expectation(description: "EventBus must NOT publish pre-init")
        unexpected.isInverted = true
        var cancellables = Set<AnyCancellable>()
        EventBus.shared.eventPublisher()
            .sink { _ in unexpected.fulfill() }
            .store(in: &cancellables)
        defer { cancellables.forEach { $0.cancel() } }

        KlaviyoOrchestration.enqueueEvent(Event(name: ._openedPush, priority: .high))

        // Give async Tasks enough time to fire if the gate were absent.
        await fulfillment(of: [unexpected], timeout: 0.5)
        let flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 0, "pre-init event must not trigger flush")
    }

    /// Initializing (`.initializing`): gate distinction from setters — publish and flush must
    /// NOT fire. This boundary differs from the identity setters' `!= .uninitialized` gate.
    @MainActor
    func testEnqueueEventInitializingNoPublishNoFlush() async {
        UnattributedBuffer.shared.reset()
        seedInitializing()
        seedTestQueueStore()
        let spyQueue = installSpyRequestQueue()

        let unexpected = expectation(description: "EventBus must NOT publish during .initializing")
        unexpected.isInverted = true
        var cancellables = Set<AnyCancellable>()
        EventBus.shared.eventPublisher()
            .sink { _ in unexpected.fulfill() }
            .store(in: &cancellables)
        defer { cancellables.forEach { $0.cancel() } }

        KlaviyoOrchestration.enqueueEvent(Event(name: ._openedPush, priority: .high))

        // Give time for any spurious publish/flush to fire.
        await fulfillment(of: [unexpected], timeout: 0.5)
        let flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 0,
                       ".initializing must not trigger flush (strict .initialized gate)")
    }

    /// Verify the event is still enqueued during `.initializing` (the gate only blocks
    /// publish/flush, not the RequestEnqueuer call).
    @MainActor
    func testEnqueueEventInitializingStillEnqueuesViaRequestEnqueuer() {
        seedInitializing()
        let readQueue = seedTestQueueStore()

        KlaviyoOrchestration.enqueueEvent(Event(name: .customEvent("init-event")))

        XCTAssertEqual(readQueue().count, 1,
                       ".initializing enqueueEvent must still enqueue via RequestEnqueuer")
    }

    /// Verify that the published EventBus event carries the stamped identity from IdentityStore.
    @MainActor
    func testEnqueueEventPostInitPublishesWithStampedIdentifiers() async {
        seedPostInit(email: "me@x.com", phoneNumber: "+15550001234", externalId: "ext-1")
        seedTestQueueStore()
        installSpyRequestQueue()

        var received: Event?
        let published = expectation(description: "EventBus event received")
        var cancellables = Set<AnyCancellable>()
        EventBus.shared.eventPublisher()
            .sink { event in
                received = event
                published.fulfill()
            }
            .store(in: &cancellables)
        defer { cancellables.forEach { $0.cancel() } }

        KlaviyoOrchestration.enqueueEvent(Event(name: .customEvent("stamped-test")))

        await fulfillment(of: [published], timeout: 2.0)
        XCTAssertEqual(received?.identifiers?.email, "me@x.com",
                       "published event must carry stamped email")
        XCTAssertEqual(received?.identifiers?.phoneNumber, "+15550001234",
                       "published event must carry stamped phone number")
        XCTAssertEqual(received?.identifiers?.externalId, "ext-1",
                       "published event must carry stamped externalId")
    }

    // MARK: - enqueueAggregateEvent

    /// Aggregate event is always forwarded to `RequestEnqueuer` with no init gate.
    @MainActor
    func testEnqueueAggregateEventRoutesToRequestEnqueuer() {
        UnattributedBuffer.shared.reset()
        // No SDKConfigStore apiKey → lands in UnattributedBuffer.
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-agg"))

        let data = Data("aggregate-payload".utf8)
        KlaviyoOrchestration.enqueueAggregateEvent(data)

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        let hasAggregate = buffered.contains {
            if case .aggregateEvent = $0 { return true }
            return false
        }
        XCTAssertTrue(hasAggregate,
                      "enqueueAggregateEvent with no apiKey must buffer in UnattributedBuffer")
    }

    // MARK: - trackingLinkReceived: resolved → openDeepLink

    /// On success, the destination URL must be forwarded to `DeepLinkManager.openDeepLink`.
    @MainActor
    func testTrackingLinkReceivedResolutionSuccessOpensDeepLink() async throws {
        seedPreInit()
        seedTestQueueStore()

        let trackingURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))

        // Stub successful network resolution.
        let responseJSON = """
        {"original_destination": "\(destinationURL.absoluteString)"}
        """
        let responseData = try XCTUnwrap(responseJSON.data(using: .utf8))
        environment.decoder = DataDecoder(jsonDecoder: JSONDecoder())
        environment.klaviyoAPI.send = { _, _ in .success(responseData) }

        let opened = expectation(description: "openDeepLink invoked with destination")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, destinationURL)
            opened.fulfill()
        }

        KlaviyoOrchestration.trackingLinkReceived(trackingURL)

        await fulfillment(of: [opened], timeout: 2.0)
    }

    // MARK: - trackingLinkReceived: failed → enqueueTrackingLinkClicked

    /// On failure, a tracking-link click-log request must be enqueued via `RequestEnqueuer`.
    @MainActor
    func testTrackingLinkReceivedResolutionFailureEnqueuesClickLog() async throws {
        seedPostInit()
        let readQueue = seedTestQueueStore()

        let trackingURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let clickTime = Date(timeIntervalSince1970: 1_735_707_600)
        environment.date = { clickTime }

        // Stub API failure.
        environment.klaviyoAPI.send = { _, _ in
            .failure(.networkError(NSError(domain: "test", code: NSURLErrorCancelled)))
        }

        // Call BEFORE starting the poll so the async Task has been enqueued in the cooperative
        // thread pool and cannot fulfill the expectation vacuously before trackingLinkReceived fires.
        KlaviyoOrchestration.trackingLinkReceived(trackingURL)

        let clickLogged = expectation(description: "click-log request enqueued")
        // Poll until QueueStore is non-empty. trackingLinkResolutionFailed → RequestEnqueuer →
        // QueueStore.enqueue is synchronous once the Task body runs; the poll just waits for
        // the cooperative scheduler to run the Task. Guard before fulfill so a timeout is a
        // loud failure instead of a vacuous pass.
        Task {
            var waited = 0
            while readQueue().isEmpty, waited < 40 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                waited += 1
            }
            guard !readQueue().isEmpty else {
                XCTFail("click-log not enqueued within timeout — trackingLinkResolutionFailed path broken")
                return
            }
            clickLogged.fulfill()
        }

        await fulfillment(of: [clickLogged], timeout: 3.0)

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1, "failed tracking link resolution must enqueue one click-log")
        guard case let .logTrackingLinkClicked(link, time, _) = queued.first?.endpoint else {
            return XCTFail("expected logTrackingLinkClicked, got \(queued.first?.endpoint as Any)")
        }
        XCTAssertEqual(link, trackingURL)
        XCTAssertEqual(time, clickTime)
    }

    // MARK: - trackingLinkResolutionFailed: direct enqueue

    /// Direct call (failure injected) must enqueue a click-log in `QueueStore` when apiKey present.
    @MainActor
    func testTrackingLinkResolutionFailedEnqueuesClickLog() throws {
        seedPostInit()
        let readQueue = seedTestQueueStore()

        let trackingURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let clickTime = Date(timeIntervalSince1970: 1_735_707_600)

        KlaviyoOrchestration.trackingLinkResolutionFailed(
            trackingLink: trackingURL,
            clickTime: clickTime
        )

        let queued = readQueue()
        XCTAssertEqual(queued.count, 1,
                       "trackingLinkResolutionFailed must enqueue exactly one click-log request")
        guard case let .logTrackingLinkClicked(link, time, _) = queued.first?.endpoint else {
            return XCTFail("expected logTrackingLinkClicked, got \(queued.first?.endpoint as Any)")
        }
        XCTAssertEqual(link, trackingURL)
        XCTAssertEqual(time, clickTime)
    }

    /// Pre-init (no apiKey): failed tracking-link resolution must buffer in `UnattributedBuffer`.
    @MainActor
    func testTrackingLinkResolutionFailedPreInitBuffers() throws {
        UnattributedBuffer.shared.reset()
        // No apiKey in SDKConfigStore → ungated path buffers in UnattributedBuffer.
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-pre"))

        let trackingURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let clickTime = environment.date()

        KlaviyoOrchestration.trackingLinkResolutionFailed(
            trackingLink: trackingURL,
            clickTime: clickTime
        )

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1,
                       "pre-init trackingLinkResolutionFailed must buffer, not drop")
        guard case let .trackingLinkClick(link, time, _) = buffered.first else {
            return XCTFail("expected .trackingLinkClick buffered entry")
        }
        XCTAssertEqual(link, trackingURL)
        XCTAssertEqual(time, clickTime)
    }
}
