//
//  OrchestrationInitializeTests.swift
//  KlaviyoSwiftTests
//
//  Created by Isobelle Lim on 9/15/26.
//
//  Parity coverage for the `initialize` + lifecycle orchestration cases ported into
//  `KlaviyoOrchestration`. Tests exercise `KlaviyoOrchestration.initialize(_:)` and
//  `KlaviyoOrchestration.completeInitialization(apiKey:)` directly.
//
//  Async tail is driven deterministically by installing a finite lifecycle publisher (via
//  `environment.appLifeCycle.lifeCycleEvents`) that terminates after a fixed sequence,
//  then `await`ing the Task returned from `initializeTask` helpers.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import Foundation
import XCTest

@MainActor
final class OrchestrationInitializeTests: StateManagementTestCase {
    private var spyQueue: SpyRequestQueue!

    override func setUp() async throws {
        try await super.setUp()
        // Reset session-scoped LifecycleState (not covered by resetCanonicalCoreStores).
        LifecycleState.shared.reset()
        spyQueue = SpyRequestQueue()
        klaviyoSwiftEnvironment.requestQueue = spyQueue
        // Install a finite lifecycle stream so `runLifecycle()` terminates deterministically.
        environment.appLifeCycle.lifeCycleEvents = {
            Empty<LifeCycleEvents, Never>().eraseToAnyPublisher()
        }
    }

    // MARK: - Helpers

    /// Installs a finite lifecycle publisher that emits `events` then completes.
    private func installLifecycle(_ events: [LifeCycleEvents]) {
        environment.appLifeCycle.lifeCycleEvents = {
            Publishers.Sequence(sequence: events).eraseToAnyPublisher()
        }
    }

    /// Calls `KlaviyoOrchestration.initialize(_:)` then awaits `completeInitialization` directly,
    /// so the full async tail (migration + drainBuffer + lifecycle loop) completes before we assert.
    ///
    /// We call `initialize` for its sync-head side effects (LifecycleState transition,
    /// SDKConfigStore update, company-switch enqueues) then drive the async tail by calling
    /// `completeInitialization` directly — a pattern that avoids the race inherent in waiting
    /// on the fire-and-forget Task spawned inside `initialize`.
    ///
    /// Safety: `completeInitialization` is now top-guarded on `LifecycleState.current == .initializing`.
    /// Whichever invocation (the internal Task or this explicit call) reaches the guard first wins;
    /// the second early-returns before touching migration, the buffer, or the lifecycle loop.
    /// migrate/drain/lifecycle therefore run EXACTLY ONCE regardless of scheduling order.
    private func callInitializeAndAwaitTail(apiKey: String) async {
        KlaviyoOrchestration.initialize(apiKey)
        // Give the internal Task a chance to begin (first yield) so LifecycleState.beginInitializing
        // is guaranteed to have run before we enter our own completeInitialization call.
        await Task.yield()
        // Directly await the full async tail. The top guard in completeInitialization ensures
        // that exactly one invocation does real work; the other is a no-op early return.
        await KlaviyoOrchestration.completeInitialization(apiKey: apiKey)
    }

    // MARK: - Cold-start fresh init

    /// Cold-start fresh initialize: `LifecycleState` transitions `.uninitialized → .initializing`
    /// synchronously (sync head), then the async tail runs migration + drainBuffer + `.initialized` +
    /// `requestQueue.start()`. We verify the SYNC head effects via SDKConfigStore, and the ASYNC
    /// tail effects via LifecycleState + requestQueue.
    func testFreshInitSetsInitializingThenInitialized() async throws {
        let apiKey = "fresh-init-key"
        // Verify sync head: SDKConfigStore set before yielding.
        // (LifecycleState.initializing is observable in production but racy in tests because the
        // async tail may complete between the `initialize` call and the next test line on a fast
        // test executor. We assert `.initialized` after awaiting the tail instead.)
        KlaviyoOrchestration.initialize(apiKey)
        XCTAssertEqual(
            SDKConfigStore.shared.current.apiKey, apiKey,
            "initialize() sync head must set SDKConfigStore.apiKey"
        )

        // Drive the async tail to completion and assert the terminal state.
        await KlaviyoOrchestration.completeInitialization(apiKey: apiKey)

        XCTAssertEqual(
            LifecycleState.shared.current, .initialized,
            "async tail must transition LifecycleState to .initialized"
        )
        // launch kickoff in runLifecycle calls start() exactly once (top guard ensures single tail).
        let startCount = await spyQueue.getStartCount()
        XCTAssertEqual(startCount, 1, "requestQueue.start() must be called exactly once on launch kickoff")
    }

    /// Same-key re-initialize: `initialize(_:)` is a no-op when LifecycleState is `.initialized`
    /// and the apiKey matches.
    func testSameKeyReInitializeIsNoOp() async throws {
        let apiKey = "same-key"
        // Drive to .initialized via direct path.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: apiKey))
        LifecycleState.shared.beginInitializing()
        await KlaviyoOrchestration.completeInitialization(apiKey: apiKey)
        XCTAssertEqual(LifecycleState.shared.current, .initialized)
        let startCount1 = await spyQueue.getStartCount()

        // Re-initialize with the same key: must be a no-op (guard apiKey != currentKey → return).
        KlaviyoOrchestration.initialize(apiKey)

        let startCount2 = await spyQueue.getStartCount()
        XCTAssertEqual(
            startCount2, startCount1,
            "same-key re-initialize must not call requestQueue.start() again"
        )
        // LifecycleState must remain .initialized (not regress to .initializing).
        XCTAssertEqual(LifecycleState.shared.current, .initialized)
    }

    /// Calling `initialize` while already `.initializing` (double-call race) must be a no-op
    /// (`beginInitializing()` returns false so no second async tail is spawned).
    /// We verify via `LifecycleState.beginInitializing()` directly (to avoid the test-timing race)
    /// and then confirm the state is not reset by a second call.
    func testDoubleInitializeDuringInitializingIsNoOp() async throws {
        let apiKey = "double-init-key"
        // Manually advance to .initializing as the sync head would.
        LifecycleState.shared.beginInitializing()
        XCTAssertEqual(LifecycleState.shared.current, .initializing)

        // Second call while still .initializing: guard in initialize() sees `.initializing` (not
        // `.uninitialized`) and the cold-start-switch block doesn't apply (no prior apiKey), so
        // `beginInitializing()` returns false → no Task spawned, state remains `.initializing`.
        KlaviyoOrchestration.initialize(apiKey)
        XCTAssertEqual(
            LifecycleState.shared.current, .initializing,
            "second initialize while .initializing must not change state"
        )
    }

    // MARK: - Runtime company switch (already .initialized, new key)

    /// Runtime company switch with a push token: must enqueue unregister(old) + re-register(new)
    /// to QueueStore and call `flushNow()`.
    func testRuntimeCompanySwitchWithTokenEnqueuesUnregisterAndReRegister() async throws {
        let oldApiKey = "old-rt-key"
        let newApiKey = "new-rt-key"
        let anonymousId = "anon-rt"
        let pushToken = "tok-rt"

        // Seed: old company, identified profile, push token.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: oldApiKey))
        IdentityStore.shared.update(ProfileData(
            email: "rt@x.com", anonymousId: anonymousId
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushToken,
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))

        // Drive to .initialized via direct completeInitialization call.
        LifecycleState.shared.beginInitializing()
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: oldApiKey))
        await KlaviyoOrchestration.completeInitialization(apiKey: oldApiKey)
        XCTAssertEqual(LifecycleState.shared.current, .initialized)

        // Register a recording QueueStore (resets prior enqueues from the init tail).
        let readQueue = seedTestQueueStore()

        // Runtime switch to new key: synchronous, all enqueues happen before `flushNow` Task.
        KlaviyoOrchestration.initialize(newApiKey)

        // SDKConfigStore must be updated to the new key.
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, newApiKey)

        // LifecycleState remains .initialized through a runtime switch.
        XCTAssertEqual(LifecycleState.shared.current, .initialized)

        // Yield to let the fire-and-forget `Task { flushNow() }` run.
        await Task.yield()
        await Task.yield()

        // flushNow must be called once for the runtime switch.
        let flushCount = await spyQueue.getFlushNowCount()
        XCTAssertEqual(flushCount, 1, "runtime company switch must call flushNow once")

        // QueueStore: unregister(old) then register(new).
        let endpoints = readQueue().map(\.endpoint)
        XCTAssertTrue(
            endpoints.contains {
                if case let .unregisterPushToken(key, _) = $0 { return key == oldApiKey }
                return false
            },
            "unregister for old company must be enqueued"
        )
        XCTAssertTrue(
            endpoints.contains {
                if case let .registerPushToken(key, _) = $0 { return key == newApiKey }
                return false
            },
            "register under new company must be enqueued"
        )
    }

    /// Runtime company switch with no push token: must not enqueue anything.
    func testRuntimeCompanySwitchWithNoTokenEnqueuesNothing() async throws {
        let oldApiKey = "old-rt-notoken"
        let newApiKey = "new-rt-notoken"

        // No push token.
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: oldApiKey))
        IdentityStore.shared.update(ProfileData(anonymousId: "anon-notoken"))
        // Drive to .initialized via direct path.
        LifecycleState.shared.beginInitializing()
        await KlaviyoOrchestration.completeInitialization(apiKey: oldApiKey)

        let readQueue = seedTestQueueStore()
        KlaviyoOrchestration.initialize(newApiKey)

        let endpoints = readQueue().map(\.endpoint)
        XCTAssertFalse(
            endpoints.contains {
                if case .unregisterPushToken = $0 { return true } else { return false }
            },
            "no unregister when no push token"
        )
        XCTAssertFalse(
            endpoints.contains {
                if case .registerPushToken = $0 { return true } else { return false }
            },
            "no register when no push token"
        )
    }

    /// Runtime company switch: after reset(preserveTokenData: true), the identity is anonymous
    /// (no PII) and a fresh anonymousId is minted for identified profiles.
    func testRuntimeCompanySwitchResetsProfileToAnonymous() async throws {
        let oldApiKey = "old-rt-reset"
        let newApiKey = "new-rt-reset"
        let oldAnon = "anon-old-reset"

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: oldApiKey))
        IdentityStore.shared.update(ProfileData(
            email: "reset@x.com",
            externalId: "ext-reset",
            anonymousId: oldAnon
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: "tok-reset",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        seedTestQueueStore()

        // Drive to .initialized via direct path.
        LifecycleState.shared.beginInitializing()
        await KlaviyoOrchestration.completeInitialization(apiKey: oldApiKey)
        seedTestQueueStore() // reset recording after init

        KlaviyoOrchestration.initialize(newApiKey)

        let identity = IdentityStore.shared.current
        XCTAssertNil(identity.email, "email must be cleared on runtime company switch reset")
        XCTAssertNil(identity.externalId, "externalId must be cleared on runtime company switch reset")
        XCTAssertNotNil(identity.anonymousId, "anonymousId must not be nil after reset")
        XCTAssertNotEqual(
            identity.anonymousId, oldAnon,
            "fresh anonymousId must be minted for identified profile on runtime switch"
        )
    }

    // MARK: - Cold-start company switch (uninitialized, persisted prior key differs)

    /// Cold-start company switch with a push token: synchronous unregister(prior) + fresh anon +
    /// token re-register(new) — all before `completeInitialization` runs.
    func testColdStartCompanySwitchWithTokenEnqueuesUnregisterAndReRegister() async throws {
        let priorApiKey = "prior-cs-key"
        let newApiKey = "new-cs-key"
        let priorAnon = "anon-cs"
        let pushToken = "tok-cs"

        // Seed the canonical stores as if a prior session left them populated.
        // LifecycleState remains .uninitialized (cold start).
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: priorApiKey))
        IdentityStore.shared.update(ProfileData(
            email: "cs@x.com",
            externalId: "ext-cs",
            anonymousId: priorAnon
        ))
        IdentityStore.shared.updatePushToken(PushTokenData(
            pushToken: pushToken,
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: environment.appContextInfo())
        ))
        let readQueue = registerRecordingQueueStore()

        // Call initialize with a NEW key (cold-start company switch).
        await callInitializeAndAwaitTail(apiKey: newApiKey)

        // Unregister(prior) must have been enqueued before completeInitialization.
        let endpoints = readQueue().map(\.endpoint)
        XCTAssertTrue(
            endpoints.contains {
                if case let .unregisterPushToken(key, _) = $0 { return key == priorApiKey }
                return false
            },
            "cold-start: unregister for prior company must be enqueued"
        )
        XCTAssertTrue(
            endpoints.contains {
                if case let .registerPushToken(key, _) = $0 { return key == newApiKey }
                return false
            },
            "cold-start: token re-register under new company must be enqueued"
        )

        // Identity after the switch: fresh anon, no PII.
        let identity = IdentityStore.shared.current
        XCTAssertNil(identity.email)
        XCTAssertNil(identity.externalId)
        XCTAssertNotEqual(identity.anonymousId, priorAnon, "fresh anon minted for cold-start switch")
    }

    /// Cold-start company switch with NO push token: no unregister or register enqueued.
    func testColdStartCompanySwitchWithNoTokenEnqueuesNothing() async throws {
        let priorApiKey = "prior-cs-notoken"
        let newApiKey = "new-cs-notoken"

        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: priorApiKey))
        IdentityStore.shared.update(ProfileData(email: "cs-nt@x.com", anonymousId: "anon-cs-nt"))
        // No push token.
        let readQueue = registerRecordingQueueStore()

        await callInitializeAndAwaitTail(apiKey: newApiKey)

        let endpoints = readQueue().map(\.endpoint)
        XCTAssertFalse(
            endpoints.contains {
                if case .unregisterPushToken = $0 { return true } else { return false }
            },
            "cold-start no-token: must not enqueue unregister"
        )
        XCTAssertFalse(
            endpoints.contains {
                if case .registerPushToken = $0 { return true } else { return false }
            },
            "cold-start no-token: must not enqueue register"
        )
    }

    // MARK: - Lifecycle loop

    //
    // These tests call `completeInitialization(apiKey:)` directly (not via `initialize(_:)`) so we
    // can `await` the full async tail — including the `for await event in ...lifecycleEventStream()`
    // loop — deterministically. The `initialize` sync head is covered by the tests above; the async
    // tail is covered here in isolation. `LifecycleState` is manually set to `.initializing` before
    // each call so `completeInitialization` accepts the transition to `.initialized`.

    /// `.foregrounded` runs handleForeground: start + push-enablement + badge.
    func testForegroundedEventCallsStart() async throws {
        installLifecycle([.foregrounded])
        LifecycleState.shared.beginInitializing()
        await KlaviyoOrchestration.completeInitialization(apiKey: "fg-test")
        let startCount = await spyQueue.getStartCount()
        XCTAssertEqual(startCount, 2, "launch kickoff + one foreground = two start calls")
    }

    /// `.backgrounded` and `.terminated` run handleBackground: stop.
    func testBackgroundedAndTerminatedCallStop() async throws {
        installLifecycle([.backgrounded, .terminated])
        LifecycleState.shared.beginInitializing()
        await KlaviyoOrchestration.completeInitialization(apiKey: "bg-test")
        let stopCount = await spyQueue.getStopCount()
        XCTAssertEqual(stopCount, 2, "background + terminate = two stop calls")
    }

    /// `.reachabilityChanged` forwards to `networkConnectivityChanged`.
    func testReachabilityChangedForwardsStatus() async throws {
        installLifecycle([
            .reachabilityChanged(status: .reachableViaWWAN),
            .reachabilityChanged(status: .notReachable)
        ])
        LifecycleState.shared.beginInitializing()
        await KlaviyoOrchestration.completeInitialization(apiKey: "reach-test")
        let statuses = await spyQueue.getConnectivityStatuses()
        XCTAssertEqual(statuses, [.reachableViaWWAN, .notReachable])
    }
}
