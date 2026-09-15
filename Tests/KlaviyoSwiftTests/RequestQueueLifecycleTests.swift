//
//  RequestQueueLifecycleTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/11/26.
//
//  Wiring coverage for the MAGE-1197 cutover: every reducer flush/lifecycle trigger drives the Core
//  `RequestQueue` actor (via `klaviyoSwiftEnvironment.requestQueue`) rather than dispatching the (now
//  dead) reducer flush-engine actions. A `SpyRequestQueue` double records the actor interactions;
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
        ProfilePropertyBuffer.shared.reset()
        spyQueue = SpyRequestQueue()
        klaviyoSwiftEnvironment.requestQueue = spyQueue
    }

    override func tearDown() async throws {
        ProfilePropertyBuffer.shared.reset()
        try await super.tearDown()
    }

    /// Installs a finite lifecycle publisher so the long-lived `completeInitialization` effect
    /// iterates the given events and then terminates (letting `store.finish()` complete).
    private func installLifecycle(_ events: [LifeCycleEvents]) {
        environment.appLifeCycle.lifeCycleEvents = {
            Publishers.Sequence(sequence: events).eraseToAnyPublisher()
        }
    }

    // MARK: - completeInitialization launch + lifecycle

    /// Launch kickoff (no further lifecycle events): actor `start` called, `.setPushEnablement`
    /// dispatched, and the badge side effect runs (autoclearing → setBadgeCount(0)).
    func testCompleteInitializationLaunchStartsQueueAndSyncsPush() async throws {
        let setBadgeExpectation = expectation(description: "BadgeManager.setBadgeCount(0) on launch")
        BadgeManager.setBadgeCountSpy = { count in
            if count == 0 { setBadgeExpectation.fulfill() }
        }
        environment.getBadgeAutoClearingSetting = { true }
        installLifecycle([]) // finite empty stream → loop ends immediately after launch kickoff

        IdentityStore.shared.update(ProfileData(anonymousId: "anon-launch"))
        let store = TestStore(
            initialState: KlaviyoState(
                apiKey: "fake-key", initalizationState: .initializing
            ),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.completeInitialization(
            KlaviyoState(apiKey: "fake-key", anonymousId: "anon-launch")
        ))
        // Long-lived effect: launch kickoff → setPushEnablement → badge, then the finite stream ends.
        await store.receive(.setPushEnablement(.authorized))
        await store.finish()

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

        IdentityStore.shared.update(ProfileData(anonymousId: "anon-fg"))
        let store = TestStore(
            initialState: KlaviyoState(
                apiKey: "fake-key", initalizationState: .initializing
            ),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.completeInitialization(
            KlaviyoState(apiKey: "fake-key", anonymousId: "anon-fg")
        ))
        await store.finish()

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

        IdentityStore.shared.update(ProfileData(anonymousId: "anon-bg"))
        let store = TestStore(
            initialState: KlaviyoState(
                apiKey: "fake-key", initalizationState: .initializing
            ),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.completeInitialization(
            KlaviyoState(apiKey: "fake-key", anonymousId: "anon-bg")
        ))
        await store.finish()

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

        IdentityStore.shared.update(ProfileData(anonymousId: "anon-reach"))
        let store = TestStore(
            initialState: KlaviyoState(
                apiKey: "fake-key", initalizationState: .initializing
            ),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        _ = await store.send(.completeInitialization(
            KlaviyoState(apiKey: "fake-key", anonymousId: "anon-reach")
        ))
        await store.finish()

        let statuses = await spyQueue.getConnectivityStatuses()
        XCTAssertEqual(statuses, [.reachableViaWWAN, .notReachable])
    }

    // MARK: - Company switch

    /// A runtime company switch prompts an immediate actor flush (instead of dispatching `.flushQueue`).
    func testCompanySwitchTriggersFlushNow() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        let newApiKey = "new-api-key"
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: initialState.apiKey!))
        IdentityStore.shared.update(initialState.identity)
        IdentityStore.shared.updatePushToken(initialState.pushTokenData)
        seedTestQueueStore()

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        _ = await store.send(.initialize(newApiKey)) {
            $0.apiKey = newApiKey
        }
        await store.finish()

        let flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 1, "company switch prompts one immediate actor flush")
    }

    // MARK: - High-priority event flush

    /// A high-priority event prompts an immediate actor flush; a standard event does NOT.
    func testHighPriorityEventTriggersFlushNowStandardDoesNot() async throws {
        let initialState = INITIALIZED_TEST_STATE()
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: initialState.apiKey!))
        IdentityStore.shared.update(initialState.identity)
        IdentityStore.shared.updatePushToken(initialState.pushTokenData)
        seedTestQueueStore()

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Standard event: no flush.
        _ = await store.send(.enqueueEvent(Event(name: .customEvent("standard"))))
        await store.finish()
        var flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 0, "standard event does not trigger an immediate flush")

        // High-priority event: one flush.
        _ = await store.send(.enqueueEvent(Event(name: ._openedPush, priority: .high)))
        await store.finish()
        flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 1, "high-priority event triggers one immediate flush")
    }

    // MARK: - setProfileProperty staging

    /// `setProfileProperty` stages into `ProfilePropertyBuffer` (the reducer holds no pending-profile).
    func testSetProfilePropertyStagesIntoBuffer() async throws {
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "pk-stage-test"))
        IdentityStore.shared.mutate { $0.anonymousId = "anon-stage" }
        seedTestQueueStore()

        let store = TestStore(
            initialState: INITIALIZED_TEST_STATE(),
            reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off

        // The reducer no longer holds a pending-profile field; staging lands in the buffer only.
        _ = await store.send(.setProfileProperty(.firstName, AnyEncodable("Blob")))

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
