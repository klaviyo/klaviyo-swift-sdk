//
//  RequestQueueLifecycleTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/11/26.
//
//  Wiring coverage for the TCA cutover: every flush/lifecycle trigger drives the Core
//  `RequestQueue` actor (via `klaviyoSwiftEnvironment.requestQueue`) through the direct
//  `KlaviyoOrchestration` functions. A `SpyRequestQueue` double records the actor interactions;
//  because it never touches `QueueStore`, tests that assert queue contents stay deterministic.
//

@testable import KlaviyoCore
import AnyCodable
import Combine
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import XCTest

@MainActor
final class RequestQueueLifecycleTests: StateManagementTestCase {
    private var spyQueue: SpyRequestQueue!

    override func setUp() async throws {
        try await super.setUp()
        LifecycleState.shared.reset()
        ProfilePropertyBuffer.shared.reset()
        spyQueue = SpyRequestQueue()
        klaviyoSwiftEnvironment.requestQueue = spyQueue
    }

    override func tearDown() async throws {
        LifecycleState.shared.reset()
        ProfilePropertyBuffer.shared.reset()
        try await super.tearDown()
    }

    /// Installs a finite lifecycle publisher so the long-lived `runLifecycle` loop iterates the
    /// given events and then terminates (letting `completeInitialization` return).
    private func installLifecycle(_ events: [LifeCycleEvents]) {
        environment.appLifeCycle.lifeCycleEvents = {
            Publishers.Sequence(sequence: events).eraseToAnyPublisher()
        }
    }

    /// Seeds a `.initializing` lifecycle + apiKey/identity so `completeInitialization` runs its
    /// launch kickoff + lifecycle loop exactly as production would after `initialize()`.
    private func seedInitializing(apiKey: String, anonymousId: String) {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(ProfileData(anonymousId: anonymousId))
        LifecycleState.shared.beginInitializing()
    }

    // MARK: - completeInitialization launch + lifecycle

    /// Launch kickoff (no further lifecycle events): actor `start` called, push enablement synced,
    /// and the badge side effect runs (autoclearing → setBadgeCount(0)).
    func testCompleteInitializationLaunchStartsQueueAndSyncsPush() async throws {
        let setBadgeExpectation = expectation(description: "BadgeManager.setBadgeCount(0) on launch")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }
        environment.getBadgeAutoClearingSetting = { true }
        installLifecycle([]) // finite empty stream → loop ends immediately after launch kickoff

        seedInitializing(apiKey: "fake-key", anonymousId: "anon-launch")
        await KlaviyoOrchestration.completeInitialization(apiKey: "fake-key")

        let startCount = await spyQueue.getStartCount()
        XCTAssertEqual(startCount, 1, "launch kickoff starts the actor once")
        let stopCount = await spyQueue.getStopCount()
        XCTAssertEqual(stopCount, 0)
        await fulfillment(of: [setBadgeExpectation], timeout: 1)
    }

    /// `.foregrounded` runs the same start + push-enablement + badge side effects as launch, so a
    /// launch followed by one foreground yields two `start` calls.
    func testForegroundedStartsQueueAgain() async throws {
        environment.getBadgeAutoClearingSetting = { true }
        installLifecycle([.foregrounded])

        seedInitializing(apiKey: "fake-key", anonymousId: "anon-fg")
        await KlaviyoOrchestration.completeInitialization(apiKey: "fake-key")

        let startCount = await spyQueue.getStartCount()
        XCTAssertEqual(startCount, 2, "launch + one foreground → two start calls")
    }

    /// `.backgrounded` / `.terminated` stop the actor and sync the badge.
    func testBackgroundedAndTerminatedStopQueue() async throws {
        let syncExpectation = expectation(description: "BadgeManager.syncBadgeCount on background/terminate")
        syncExpectation.expectedFulfillmentCount = 2
        BadgeManager.syncBadgeCountSpy = { syncExpectation.fulfill() }
        environment.getBadgeAutoClearingSetting = { true }
        installLifecycle([.backgrounded, .terminated])

        seedInitializing(apiKey: "fake-key", anonymousId: "anon-bg")
        await KlaviyoOrchestration.completeInitialization(apiKey: "fake-key")

        let stopCount = await spyQueue.getStopCount()
        XCTAssertEqual(stopCount, 2, "background + terminate → two stop calls")
        let startCount = await spyQueue.getStartCount()
        XCTAssertEqual(startCount, 1, "only the launch kickoff starts the actor")
        await fulfillment(of: [syncExpectation], timeout: 1)
    }

    /// `.reachabilityChanged` forwards the status to the actor's `networkConnectivityChanged`.
    func testReachabilityChangedForwardsStatus() async throws {
        environment.getBadgeAutoClearingSetting = { true }
        installLifecycle([
            .reachabilityChanged(status: .reachableViaWWAN),
            .reachabilityChanged(status: .notReachable)
        ])

        seedInitializing(apiKey: "fake-key", anonymousId: "anon-reach")
        await KlaviyoOrchestration.completeInitialization(apiKey: "fake-key")

        let statuses = await spyQueue.getConnectivityStatuses()
        XCTAssertEqual(statuses, [.reachableViaWWAN, .notReachable])
    }

    // MARK: - Company switch

    /// A runtime company switch prompts an immediate actor flush.
    func testCompanySwitchTriggersFlushNow() async throws {
        let apiKey = TEST_API_KEY
        let newApiKey = "new-api-key"
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        IdentityStore.shared.update(ProfileData(anonymousId: environment.uuid().uuidString))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "blob_token",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        seedTestQueueStore()
        // Advance to `.initialized` so `initialize` takes the runtime-company-switch branch.
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()

        KlaviyoOrchestration.initialize(newApiKey)
        // The flush is dispatched on an unstructured Task; give it a beat to reach the spy.
        try await waitForConditionOrFail { await self.spyQueue.getFlushNowCount() == 1 }

        let flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 1, "company switch prompts one immediate actor flush")
    }

    // MARK: - High-priority event flush

    /// A high-priority event prompts an immediate actor flush; a standard event does NOT.
    func testHighPriorityEventTriggersFlushNowStandardDoesNot() async throws {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: environment.uuid().uuidString))
        seedTestQueueStore()
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()

        // Standard event: no flush.
        KlaviyoOrchestration.enqueueEvent(Event(name: .customEvent("standard")))
        try await Task.sleep(nanoseconds: 100_000_000)
        var flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 0, "standard event does not trigger an immediate flush")

        // High-priority event: one flush.
        KlaviyoOrchestration.enqueueEvent(Event(name: ._openedPush, priority: .high))
        try await waitForConditionOrFail { await self.spyQueue.getFlushNowCount() == 1 }
        flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 1, "high-priority event triggers one immediate flush")
    }

    // MARK: - setProfileProperty staging

    /// `setProfileProperty` stages into `ProfilePropertyBuffer`.
    func testSetProfilePropertyStagesIntoBuffer() async throws {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-stage-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-stage" }
        seedTestQueueStore()

        KlaviyoOrchestration.setProfileProperty(.firstName, AnyEncodable("Blob"))

        // `flushIntoQueue` only ENQUEUES (it never calls `klaviyoAPI.send`), so inspect the QueueStore
        // directly and assert the staged property was folded into the enqueued request's payload.
        await ProfilePropertyBuffer.shared.flushIntoQueue()
        let firstNames: [String?] = QueueStore.shared.requests.map { request in
            switch request.endpoint {
            case let .registerPushToken(_, payload):
                return payload.data.attributes.profile.data.attributes.firstName
            case let .createProfile(_, payload):
                return payload.data.attributes.firstName
            default:
                return nil
            }
        }
        XCTAssertTrue(
            firstNames.contains("Blob"),
            "staged firstName must be folded into a queued createProfile/registerPushToken payload"
        )
    }
}
