//
//  RequestQueueLaneTests.swift
//  klaviyo-swift-sdk
//
//  MAGE-842 lane-scheduler POC: tests for lane classification, per-lane leasing/FIFO, the global
//  in-flight bound, lane-local retry isolation, round-robin fairness, and restart reclassification.
//

@testable import KlaviyoCore
import XCTest

final class RequestQueueLaneTests: XCTestCase {
    private var fileIO: FileIODouble!

    override func setUp() {
        super.setUp()
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
        // An apiKey is required for `flush()` to run (pre-init flushing stays gated).
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "test-api-key"))
    }

    override func tearDown() {
        SDKConfigStore.shared.reset()
        IdentityStore.shared.reset()
        QueueStore.resetShared()
        fileIO = nil
        environment = KlaviyoEnvironment.test()
        super.tearDown()
    }

    // MARK: - Lane classification

    /// Every endpoint maps to its lane per the MAGE-842 lane table. The mapping lives in one place
    /// (`KlaviyoEndpoint.lane`), so remapping is a one-line change; this pins the current table.
    func testLaneClassificationForEveryEndpoint() throws {
        let profile = KlaviyoEndpoint.createProfile("k", CreateProfilePayload(data: .test))
        let register = KlaviyoEndpoint.registerPushToken(
            "k",
            PushTokenPayload(
                pushToken: "tok",
                enablement: PushEnablement.authorized.rawValue,
                background: PushBackground.available.rawValue,
                profile: ProfilePayload(anonymousId: "anon-1")
            )
        )
        let unregister = KlaviyoEndpoint.unregisterPushToken(
            "k", UnregisterPushTokenPayload(pushToken: "tok", anonymousId: "anon-1")
        )
        let subscription = KlaviyoEndpoint.createSubscription(
            "k", CreateSubscriptionPayload(listId: "list-1", profile: ProfilePayload(anonymousId: "anon-1"))
        )
        let event = KlaviyoEndpoint.createEvent("k", CreateEventPayload(data: .init(name: "e")))
        let aggregate = KlaviyoEndpoint.aggregateEvent("k", Data("[]".utf8))
        let trackingLink = try XCTUnwrap(URL(string: "https://klaviyo.com/track"))
        let click = KlaviyoEndpoint.logTrackingLinkClicked(
            trackingLink: trackingLink,
            clickTime: Date(timeIntervalSince1970: 0),
            profileInfo: ProfilePayload(anonymousId: "anon-1")
        )
        let resolve = KlaviyoEndpoint.resolveDestinationURL(
            trackingLink: trackingLink,
            profileInfo: ProfilePayload(anonymousId: "anon-1")
        )
        let geofences = KlaviyoEndpoint.fetchGeofences("k", latitude: 1, longitude: 2)

        // IDENTITY: profiles, push-tokens, push-token-unregister, subscriptions. (A profile change
        // folded into a registerPushToken request stays in identity.)
        XCTAssertEqual(profile.lane, .identity)
        XCTAssertEqual(register.lane, .identity)
        XCTAssertEqual(unregister.lane, .identity)
        XCTAssertEqual(subscription.lane, .identity)
        // EVENTS: /client/events.
        XCTAssertEqual(event.lane, .events)
        // ENGAGEMENT: /onsite/track-analytics and tracking-link click logging.
        XCTAssertEqual(aggregate.lane, .engagement)
        XCTAssertEqual(click.lane, .engagement)
        // Never enqueued to QueueStore; mapped only so the switch is total.
        XCTAssertEqual(resolve.lane, .engagement)
        XCTAssertEqual(geofences.lane, .engagement)
    }

    // MARK: - FIFO within a lane

    /// Requests on the same lane drain and send in enqueue order (FIFO), even interleaved with
    /// other lanes' requests in the store.
    func testFifoWithinLane() async {
        QueueStore.register(makeQueueStore())
        let sendSpy = LaneSendSpy()
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-2"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-2"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-3"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        await queue.flushNow()

        XCTAssertEqual(sendSpy.sentIds(for: .identity), ["id-1", "id-2", "id-3"],
                       "identity lane drains head-first in FIFO order")
        XCTAssertEqual(sendSpy.sentIds(for: .events), ["ev-1", "ev-2"],
                       "events lane drains head-first in FIFO order")
        XCTAssertEqual(sendSpy.sentIds.sorted(), ["ev-1", "ev-2", "id-1", "id-2", "id-3"],
                       "every request across both lanes is sent exactly once")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "store drained after a successful pass")
    }

    // MARK: - One in flight per lane

    /// A slow in-flight identity send must not block an events request from starting (within the
    /// global bound): the pass moves on to the events lane while identity's send is still parked,
    /// and events completes before identity's response ever returns.
    func testOneLaneInFlightDoesNotBlockAnotherLane() async {
        QueueStore.register(makeQueueStore())
        let identityParked = expectation(description: "identity send parked mid-flight")
        let parkingIdentity = SendSpy(parkFirstCall: true, started: identityParked)
        let lanes = LaneSendSpy()
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        // Route identity sends through the parking spy (a slow response), events through a plain spy.
        let queue = RequestQueue(clock: .immediate) { request, info in
            if request.endpoint.lane == .identity {
                return await parkingIdentity.send(request, info)
            }
            return await lanes.send(request, info)
        }

        let flush = Task.detached { await queue.flushNow() }
        await fulfillment(of: [identityParked], timeout: 2.0)

        // Identity is parked mid-flight; the pass must still have started (and finished) events.
        // Lanes drain concurrently, so wait (bounded) for the events send rather than assume it
        // landed before the identity send parked.
        XCTAssertTrue(lanes.waitForSends(on: .events, atLeast: 1),
                      "an in-flight identity response must not stop an events request from starting")
        XCTAssertEqual(lanes.sentIds(for: .events), ["ev-1"])
        XCTAssertEqual(spyCount(parkingIdentity), 1, "at most one identity request in flight")

        parkingIdentity.release()
        await flush.value
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "both lanes drained once identity resumes")
    }

    /// Within one lane, sends are strictly sequential: the second request on a lane is not sent
    /// until the first resolves (one in flight per lane).
    func testOneInFlightPerLane() async {
        QueueStore.register(makeQueueStore())
        let headParked = expectation(description: "lane head parked mid-flight")
        let sendSpy = SendSpy(parkFirstCall: true, started: headParked)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-2"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        let flush = Task.detached { await queue.flushNow() }
        await fulfillment(of: [headParked], timeout: 2.0)

        XCTAssertEqual(sendSpy.sentIds, ["ev-1"],
                       "the lane's second request must not start while its head is in flight")

        sendSpy.release()
        await flush.value
        XCTAssertEqual(sendSpy.sentIds, ["ev-1", "ev-2"], "the lane drains sequentially, head first")
    }

    // MARK: - Global bound

    /// With every lane populated, a single pass sends at most `maxLanesInFlight` (3) requests in
    /// flight — here, exactly one per lane across all three lanes — and never exceeds the bound.
    func testGlobalInFlightBoundNeverExceedsThree() async {
        QueueStore.register(makeQueueStore())
        let sendSpy = LaneSendSpy()
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeAggregateEventRequest(id: "ag-1"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        await queue.flushNow()

        XCTAssertEqual(sendSpy.sentIds.count, 3, "one request per lane, all three lanes served")
        XCTAssertEqual(Set(sendSpy.sentLanes).count, 3, "all three lanes in flight this pass")
        XCTAssertLessThanOrEqual(Set(sendSpy.sentLanes).count, FlushConstants.maxLanesInFlight,
                                 "in-flight lanes never exceed the global bound")
    }

    // MARK: - Retry isolation

    /// A transient failure on one lane advances ONLY that lane's retry state; other lanes still
    /// drain the same pass, and on the next tick the failed lane retries at an advanced attempt
    /// number while a fresh request on another lane still sends at the initial attempt.
    func testTransientFailureIsolatesRetryStatePerLane() async {
        QueueStore.register(makeQueueStore())
        // Identity fails on its first send, then succeeds (the script's last result repeats).
        let sendSpy = LaneSendSpy(resultsByLane: [
            .identity: [.failure(.networkError(NSError(domain: "test", code: -1))), .success(Data())]
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        // Tick 1: identity fails transiently and is restored; events still drains this same pass.
        await queue.flushNow()
        XCTAssertEqual(sendSpy.sentIds(for: .identity), ["id-1"])
        XCTAssertEqual(sendSpy.sentIds(for: .events), ["ev-1"],
                       "an identity failure must not stop the events lane from draining")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["id-1"],
                       "only the failed identity request is restored")

        // Tick 2: identity retries (succeeds) at an ADVANCED attempt, while a fresh event sends at
        // the INITIAL attempt — the two lanes' retry bookkeeping is independent.
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-2"), persist: .synchronous)
        await queue.flushNow()
        XCTAssertEqual(sendSpy.sentIds(for: .identity), ["id-1", "id-1"])
        XCTAssertEqual(sendSpy.sentIds(for: .events), ["ev-1", "ev-2"],
                       "events keeps draining on the next tick")
        let identityAttempts = zip(sendSpy.sentLanes, sendSpy.sentAttempts)
            .compactMap { $0 == .identity ? $1 : nil }
        let eventsAttempts = zip(sendSpy.sentLanes, sendSpy.sentAttempts)
            .compactMap { $0 == .events ? $1 : nil }
        XCTAssertEqual(identityAttempts, [1, 2],
                       "the failing lane's attempt count advances in isolation")
        XCTAssertEqual(eventsAttempts, [1, 1],
                       "another lane's attempt count is unaffected by identity's retry")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "all lanes drained by the second tick")
    }

    /// A rate-limit backoff gates ONLY the failing lane: while identity's backoff counts down over
    /// ticks, events keeps draining every tick. The identity lane's next-eligible time advances per
    /// its own gate; the events lane is never delayed by it.
    func testRateLimitBackoffGatesOnlyTheFailingLane() async {
        QueueStore.register(makeQueueStore())
        // backoff 25s, wifi interval 10s → identity gate needs 25→15→5→0 across its visits.
        let sendSpy = LaneSendSpy(resultsByLane: [
            .identity: [.failure(.rateLimitError(backOff: 25)), .success(Data())]
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        // Tick 1: identity rate-limits and restores; events drains unaffected.
        await queue.flushNow()
        XCTAssertEqual(sendSpy.sentIds(for: .identity), ["id-1"])
        XCTAssertEqual(sendSpy.sentIds(for: .events), ["ev-1"],
                       "events drains while identity's backoff begins")

        // Ticks 2 & 3: identity's backoff counts down (25→15→5) and the lane is skipped — but a
        // fresh event enqueued during the wait still sends on the very next tick.
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-2"), persist: .synchronous)
        await queue.flushNow()
        await queue.flushNow()
        XCTAssertEqual(sendSpy.sentIds(for: .identity), ["id-1"],
                       "identity is not resent while its backoff counts down")
        XCTAssertEqual(sendSpy.sentIds(for: .events), ["ev-1", "ev-2"],
                       "a retrying lane must not delay another lane's wake-up")

        // Tick 4: identity's backoff elapses (5→0); it resends and succeeds.
        await queue.flushNow()
        XCTAssertEqual(sendSpy.sentIds(for: .identity), ["id-1", "id-1"],
                       "identity resends once its own backoff elapses")
        let identityAttempts = zip(sendSpy.sentLanes, sendSpy.sentAttempts)
            .compactMap { $0 == .identity ? $1 : nil }
        XCTAssertEqual(identityAttempts, [1, 2], "identity's attempt number advanced across the backoff")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "all lanes drained by the final tick")
    }

    // MARK: - Fairness

    /// Selection rotates round-robin: the lane after the last one served leads the next pass. A
    /// parking identity send makes the first pass end deterministically on events (identity parks
    /// mid-flight while events drains), so the next pass must lead with events — not dictionary
    /// order and not the lane that led the previous pass.
    func testRoundRobinRotatesLeadLane() async {
        QueueStore.register(makeQueueStore())
        let identityParked = expectation(description: "identity send parked mid-flight")
        let parkingIdentity = SendSpy(parkFirstCall: true, started: identityParked)
        let lanes = LaneSendSpy()
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate) { request, info in
            if request.endpoint.lane == .identity {
                return await parkingIdentity.send(request, info)
            }
            return await lanes.send(request, info)
        }

        // Pass 1: identity parks mid-flight; events drains first. On resume, identity finishes last,
        // so events is the last lane SERVED. (Both lanes end up sent exactly once.)
        let flush1 = Task.detached { await queue.flushNow() }
        await fulfillment(of: [identityParked], timeout: 2.0)
        XCTAssertTrue(lanes.waitForSends(on: .events, atLeast: 1),
                      "events drains while identity is parked, ending the pass on events")
        parkingIdentity.release()
        await flush1.value

        // Pass 2: with events the last-served lane, selection rotates to lead with events.
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-2"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-2"), persist: .synchronous)
        await queue.flushNow()

        XCTAssertEqual(lanes.sentIds(for: .events), ["ev-1", "ev-2"],
                       "both events sent across the two passes")
        XCTAssertEqual(spyCount(parkingIdentity), 2, "both identity sends across the two passes")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "no starvation: both lanes fully drain")
    }

    /// A continuously failing lane cannot starve the others: identity fails transiently on every
    /// tick, yet events keeps draining every tick indefinitely.
    func testContinuouslyFailingLaneDoesNotStarveOthers() async {
        QueueStore.register(makeQueueStore())
        // No success scripted for identity: the last (and only) result — a network error — repeats.
        let sendSpy = LaneSendSpy(resultsByLane: [
            .identity: [.failure(.networkError(NSError(domain: "test", code: -1)))]
        ])
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-stuck"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)

        await queue.flushNow()
        // Enqueue a fresh event each tick; each must send despite identity failing every tick.
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-2"), persist: .synchronous)
        await queue.flushNow()
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-3"), persist: .synchronous)
        await queue.flushNow()

        XCTAssertEqual(sendSpy.sentIds(for: .events), ["ev-1", "ev-2", "ev-3"],
                       "events drains every tick while identity keeps failing")
        XCTAssertEqual(sendSpy.sentIds(for: .identity).count, 3,
                       "identity is retried each tick (restored, never dropped)")
        XCTAssertEqual(QueueStore.shared.requests.map(\.id), ["id-stuck"],
                       "only the failing identity request remains")
    }

    // MARK: - Restart reclassification

    /// A persisted mixed queue reclassifies into the same lanes after a restart (a fresh
    /// `QueueStore` hydrating from the persisted file): no migration, nothing new persisted — the
    /// lane is derived from each request's endpoint at restore, and each lane drains once.
    func testRestartReclassifiesPersistedQueueIntoLanes() async {
        let diskSpy = WriteSpyDiskIO()
        QueueStore.register(makeQueueStore(diskIO: diskSpy))
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeEventRequest(id: "ev-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeAggregateEventRequest(id: "ag-1"), persist: .synchronous)
        QueueStore.shared.enqueue(makeCreateProfileRequest(id: "id-2"), persist: .synchronous)

        // Restart: a fresh store hydrates from the persisted bytes (lane derived per request at load).
        let persisted = diskSpy.stored
        XCTAssertEqual(persisted.map(\.id), ["id-1", "ev-1", "ag-1", "id-2"],
                       "one persisted queue, unchanged storage format, no lane field written")
        QueueStore.register(QueueStore(
            diskIO: QueueStore.DiskIO(load: { persisted }, save: { _ in }),
            scheduler: QueueStore.PersistScheduler { _, work in work() },
            emitWarning: { _ in }
        ))

        let sendSpy = LaneSendSpy()
        let queue = RequestQueue(clock: .immediate, send: sendSpy.send)
        await queue.flushNow()

        XCTAssertEqual(sendSpy.sentIds(for: .identity), ["id-1", "id-2"],
                       "persisted identity requests reclassify to identity and drain FIFO")
        XCTAssertEqual(sendSpy.sentIds(for: .events), ["ev-1"],
                       "persisted event reclassifies to events")
        XCTAssertEqual(sendSpy.sentIds(for: .engagement), ["ag-1"],
                       "persisted aggregate event reclassifies to engagement")
        XCTAssertEqual(sendSpy.sentIds.count, 4, "each persisted request drains exactly once")
        XCTAssertTrue(QueueStore.shared.requests.isEmpty, "all lanes drained after reclassification")
    }

    // MARK: - Helpers

    private func spyCount(_ sendSpy: SendSpy) -> Int {
        sendSpy.sentIds.count
    }
}
