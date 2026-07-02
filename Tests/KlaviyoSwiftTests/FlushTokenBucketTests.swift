//
//  FlushTokenBucketTests.swift
//
//  Tests for the demand-adaptive (token-bucket) flush governor and the
//  queue-depth early-flush trigger.
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

final class FlushTokenBucketTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    private func sampleRequest(name: String = "test") -> KlaviyoRequest {
        KlaviyoRequest(endpoint: .createEvent("foo", CreateEventPayload(data: .init(name: name))))
    }

    // MARK: - consumeFlushToken(currentTime:)

    func test_consumeFlushToken_fullBucketAllowsFlushAndDecrementsByOne() {
        var state = KlaviyoState(queue: [])
        state.flushInterval = StateManagementConstants.wifiFlushInterval

        let flushTime = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(state.consumeFlushToken(currentTime: flushTime))
        XCTAssertEqual(
            state.availableFlushTokens,
            StateManagementConstants.flushTokenBucketCapacity - 1,
            accuracy: 0.0001
        )
        XCTAssertEqual(state.lastFlushTokenRefill, flushTime)
    }

    func test_consumeFlushToken_emptyBucketIsDeniedUntilEnoughTimeElapses() {
        var state = KlaviyoState(queue: [])
        state.flushInterval = StateManagementConstants.wifiFlushInterval // 10s -> 0.1 token/sec
        state.availableFlushTokens = 0
        let start = Date(timeIntervalSince1970: 1000)
        state.lastFlushTokenRefill = start

        // After 5s only half a token has accrued -> still denied.
        XCTAssertFalse(state.consumeFlushToken(currentTime: start.addingTimeInterval(5)))
        XCTAssertEqual(state.availableFlushTokens, 0.5, accuracy: 0.0001)

        // 10 more seconds accrues a full token -> allowed, then decremented.
        XCTAssertTrue(state.consumeFlushToken(currentTime: start.addingTimeInterval(15)))
        XCTAssertEqual(state.availableFlushTokens, 0.5, accuracy: 0.0001)
    }

    func test_consumeFlushToken_refillIsCappedAtCapacity() {
        var state = KlaviyoState(queue: [])
        state.flushInterval = StateManagementConstants.wifiFlushInterval
        state.availableFlushTokens = 4
        let start = Date(timeIntervalSince1970: 1000)
        state.lastFlushTokenRefill = start

        // 100s would add 10 tokens, but the bucket is capped at capacity before consuming.
        XCTAssertTrue(state.consumeFlushToken(currentTime: start.addingTimeInterval(100)))
        XCTAssertEqual(
            state.availableFlushTokens,
            StateManagementConstants.flushTokenBucketCapacity - 1,
            accuracy: 0.0001
        )
    }

    func test_consumeFlushToken_doesNotRefillWhenOffline() {
        var state = KlaviyoState(queue: [])
        state.flushInterval = .infinity // offline: timer paused, bucket frozen
        state.availableFlushTokens = 0
        let start = Date(timeIntervalSince1970: 1000)
        state.lastFlushTokenRefill = start

        XCTAssertFalse(state.consumeFlushToken(currentTime: start.addingTimeInterval(10_000)))
        XCTAssertEqual(state.availableFlushTokens, 0, accuracy: 0.0001)
        XCTAssertEqual(state.lastFlushTokenRefill, start.addingTimeInterval(10_000))
    }

    /// A backward clock jump (manual clock change, NTP correction) must not rewind
    /// `lastFlushTokenRefill`, or a later call using the "real" (forward) time would compute an
    /// inflated `elapsed` and grant a windfall refill instead of being correctly denied.
    func test_consumeFlushToken_backwardClockJumpDoesNotGrantWindfallRefill() {
        var state = KlaviyoState(queue: [])
        state.flushInterval = StateManagementConstants.wifiFlushInterval // 10s -> 0.1 token/sec
        state.availableFlushTokens = 0
        let start = Date(timeIntervalSince1970: 1000)
        state.lastFlushTokenRefill = start

        // Clock jumps backward: elapsed is negative so no tokens accrue, and the refill
        // timestamp must NOT rewind to this earlier time.
        XCTAssertFalse(state.consumeFlushToken(currentTime: start.addingTimeInterval(-500)))
        XCTAssertEqual(state.availableFlushTokens, 0, accuracy: 0.0001)
        XCTAssertEqual(state.lastFlushTokenRefill, start)

        // Clock returns to the original time. If the timestamp had rewound to -500s, this call
        // would see a fabricated 500s elapsed and grant a windfall refill. It must still be denied.
        XCTAssertFalse(state.consumeFlushToken(currentTime: start))
        XCTAssertEqual(state.availableFlushTokens, 0, accuracy: 0.0001)
        XCTAssertEqual(state.lastFlushTokenRefill, start)
    }

    // MARK: - shouldFlushForQueueDepth

    func test_shouldFlushForQueueDepth_belowThresholdIsFalse() {
        let queue = Array(repeating: sampleRequest(), count: StateManagementConstants.flushDepth - 1)
        var state = KlaviyoState(queue: queue)
        state.flushInterval = StateManagementConstants.wifiFlushInterval
        XCTAssertFalse(state.shouldFlushForQueueDepth)
    }

    func test_shouldFlushForQueueDepth_atThresholdIsTrue() {
        let queue = Array(repeating: sampleRequest(), count: StateManagementConstants.flushDepth)
        var state = KlaviyoState(queue: queue)
        state.flushInterval = StateManagementConstants.wifiFlushInterval
        XCTAssertTrue(state.shouldFlushForQueueDepth)
    }

    func test_shouldFlushForQueueDepth_isFalseWhenOffline() {
        let queue = Array(repeating: sampleRequest(), count: StateManagementConstants.flushDepth)
        var state = KlaviyoState(queue: queue)
        state.flushInterval = .infinity
        XCTAssertFalse(state.shouldFlushForQueueDepth)
    }

    // MARK: - flushQueue token gate (reducer)

    @MainActor
    func test_flushQueue_withDepletedBucketDoesNotFlush() async {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        initialState.availableFlushTokens = 0
        // Refilled "now", so no time has elapsed at flush time -> no token accrues.
        initialState.lastFlushTokenRefill = environment.date()
        initialState.queue = [initialState.buildProfileRequest(
            apiKey: initialState.apiKey!,
            anonymousId: initialState.anonymousId!
        )]
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        // Bucket is empty and nothing refills, so the flush is deferred:
        // no state change and, crucially, no `.sendRequest` is emitted.
        _ = await store.send(.flushQueue)
    }

    // MARK: - queue-depth early-flush trigger (reducer)

    @MainActor
    func test_enqueueAggregateEventReachingQueueDepthTriggersFlush() async {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        // Empty the bucket so the triggered flush is gated. This keeps the test focused on the
        // depth trigger itself rather than the downstream send cascade.
        initialState.availableFlushTokens = 0
        initialState.queue = Array(
            repeating: sampleRequest(name: "filler"),
            count: StateManagementConstants.flushDepth - 1
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Enqueuing one more request reaches `flushDepth`, which schedules an early flush.
        await store.send(.enqueueAggregateEvent(Data("agg".utf8)))
        await store.receive(.flushQueue)
    }

    /// Regression test: while a server-mandated `Retry-After` backoff is active, the queue-depth
    /// trigger must NOT fire `.flushQueue` at all — each call to `.flushQueue` erodes
    /// `currentBackoff` by a full flush interval, so a depth trigger firing on every enqueued
    /// event during high traffic would eat through the backoff window far faster than the
    /// server intended.
    @MainActor
    func test_shouldFlushForQueueDepth_doesNotErodeBackoffOnRepeatedEnqueues() async {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        initialState.retryState = .retryWithBackoff(requestCount: 1, totalRetryCount: 1, currentBackoff: 60)
        initialState.queue = Array(
            repeating: sampleRequest(name: "filler"),
            count: StateManagementConstants.flushDepth - 1
        )
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        // Each of these enqueues would, pre-fix, reach/exceed `flushDepth` and trigger a
        // `.flushQueue` cascade that erodes `currentBackoff` by a full flush interval per call.
        for index in 0..<6 {
            await store.send(.enqueueAggregateEvent(Data("agg\(index)".utf8)))
        }

        // No `.flushQueue` should have fired from the depth trigger while backoff is active, so
        // `currentBackoff` must be untouched.
        guard case let .retryWithBackoff(_, _, backoff) = store.state.retryState else {
            XCTFail("Expected retryState to remain .retryWithBackoff")
            return
        }
        XCTAssertEqual(backoff, 60)
    }

    // MARK: - prioritized (opened-push/geofence) flushes bypass the token gate

    /// Verifies that a prioritized engagement event (opened-push) flushes immediately even when
    /// the token bucket is fully depleted — engagement events must never wait on the bucket, and
    /// bypassing the gate means they don't spend a token either.
    @MainActor
    func test_openedPushEvent_withDepletedBucket_flushesAnyway() async {
        var initialState = INITIALIZED_TEST_STATE()
        initialState.flushing = false
        initialState.availableFlushTokens = 0
        // Refilled "now", so no time elapses before the flush attempt -> no token would accrue
        // through the normal gate.
        initialState.lastFlushTokenRefill = environment.date()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let event = Event(name: ._openedPush)
        await store.send(.enqueueEvent(event))

        // The prioritized flush bypasses the token gate entirely, so it proceeds despite the
        // depleted bucket.
        await store.receive(.flushQueue)

        XCTAssertTrue(store.state.flushing)
        XCTAssertTrue(store.state.queue.isEmpty)
        XCTAssertEqual(store.state.requestsInFlight.count, 1)
        // Bypassing the gate means no token is spent — the bucket stays exactly as depleted.
        XCTAssertEqual(store.state.availableFlushTokens, 0, accuracy: 0.0001)
    }

    // MARK: - token bucket reset on company switch

    /// Verifies that re-initializing with a *different* API key resets the token bucket to
    /// full capacity, so a depleted bucket from the previous company cannot throttle the
    /// incoming company's first flush cycle.
    ///
    /// When `.initialize` is dispatched against an already-initialized state with a new key,
    /// the reducer resets profile data and restores the bucket, then returns `.none` (it
    /// cannot transition to `.initializing` because `initalizationState` is no longer
    /// `.uninitialized`). The state is verified synchronously via the `send` expectation
    /// before any async work fires.
    @MainActor
    func test_initialize_withNewApiKey_resetsBucketToFull() async {
        // Start with an already-initialized state whose bucket is fully depleted.
        var initialState = INITIALIZED_TEST_STATE()
        initialState.availableFlushTokens = 0
        initialState.lastFlushTokenRefill = environment.date()

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off

        let newApiKey = "new-company-key"
        await store.send(.initialize(newApiKey)) {
            // The bucket must be restored to full capacity on a company switch.
            $0.availableFlushTokens = StateManagementConstants.flushTokenBucketCapacity
            $0.lastFlushTokenRefill = nil
            $0.apiKey = newApiKey
            // initalizationState stays .initialized — the guard in .initialize exits early
            // because the state is not .uninitialized after the company-switch branch runs.
        }
    }
}
