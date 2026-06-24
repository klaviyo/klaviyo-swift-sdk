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
}
