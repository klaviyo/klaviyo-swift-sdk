//
//  RequestQueue.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

/// Core-owned flush engine: drains `QueueStore.shared` on a timed cadence and sends through an
/// injected transport.
///
/// Lane-scheduler POC: `flush()` leases one batch PER LANE (`QueueStore.drain(lane:)`) and
/// drains each lane on its own task (`drainLane(_:)`), so a slow in-flight send on one lane never
/// blocks another lane's sends. Each lane has its own retry bookkeeping, so a retrying or
/// backing-off lane never delays another lane's wake-up either: on a retryable failure the lane's
/// lease is restored and that lane stops, but the other lanes keep draining. At most
/// `FlushConstants.maxLanesInFlight` (3) lanes are in flight concurrently, selected round-robin
/// from the lane after the last one served, so no lane starves. On success a request is dequeued;
/// on failure it is classified and either dequeued (non-retryable), restored with a lane-local
/// retry count (transient), or restored with a lane-local absolute backoff deadline
/// (`laneDeadlines`) that the per-lane gate in `flush()` waits out before resending
/// (rate-limit / server error). A one-shot `deadlineWake` task fires at the earliest outstanding
/// deadline so a lane resumes AT its deadline rather than up to one flush interval late on the
/// periodic tick; the periodic tick is unchanged for normal traffic.
public actor RequestQueue {
    /// Transport seam: sends one request with its per-attempt retry metadata and reports the result.
    public typealias Send = @Sendable (KlaviyoRequest, RequestAttemptInfo)
        async -> Result<Data, KlaviyoAPIError>

    /// A lane's leased batch plus its send task. The batch is mutated only by that task, so a lane
    /// is FIFO and at most one request per lane is in flight; the task handle lets `flush()` await
    /// the whole pass and `stop()` cancel in-flight sends before restoring leases.
    private struct LaneDrain {
        var batch: [KlaviyoRequest]
        var task: Task<Void, Never>
    }

    // MARK: - Injected dependencies

    private let clock: SleepClock
    private let send: Send
    /// Optional hook invoked before each drain; wired at bootstrap to
    /// `ProfilePropertyBuffer.flushIntoQueue` so staged profile properties fold in before the drain.
    private let willDrain: (@Sendable () async -> Void)?

    // MARK: - Owned state

    /// Per-lane drains leased out of `QueueStore` for the current pass. Restored to the store on
    /// `stop()` (or on a lane's retryable failure) so a shutdown mid-flush never drops them.
    private var lanes: [RequestLane: LaneDrain] = [:]
    /// Current cadence between flushes. Defaults to the wifi interval; adjusted by
    /// `networkConnectivityChanged` (wifi/cellular interval, or `.infinity` when offline).
    private var flushInterval: TimeInterval = FlushConstants.wifiFlushInterval
    /// Retry bookkeeping per lane; only the lane whose send failed advances. A missing entry is a
    /// fresh lane at `.retry(FlushConstants.initialAttempt)`.
    private var laneRetryStates: [RequestLane: RetryState] = [:]
    /// Absolute per-lane backoff deadlines: a lane with an entry resends no earlier than this
    /// instant. Runtime-only (never persisted) and cleared with the lane's retry state. Computed at
    /// failure time from the injected clock, so a lane resumes at its deadline regardless of the
    /// flush cadence (replacing the old interval-countdown gate, which could fire up to one
    /// interval late — or early under bursts of immediate flushes).
    private var laneDeadlines: [RequestLane: Date] = [:]
    /// One-shot wake scheduled at the earliest outstanding lane deadline; cancelled/replaced when a
    /// new earlier deadline is recorded and cancelled on `stop()`.
    private var deadlineWake: Task<Void, Never>?
    /// Round-robin cursor: the position (into `RequestLane.allCases`) of the lane served LAST.
    /// Selection starts at the next lane so a continuously failing lane cannot starve the others.
    private var lastServedLaneIndex: Int?
    /// The active run loop, or `nil` when stopped.
    private var runLoop: Task<Void, Never>?
    private var isFlushing = false

    public init(
        clock: SleepClock,
        send: @escaping Send,
        willDrain: (@Sendable () async -> Void)? = nil
    ) {
        self.clock = clock
        self.send = send
        self.willDrain = willDrain
    }

    // MARK: - Lifecycle

    /// (Re)starts the run loop. Any existing loop is cancelled first so `start()` is idempotent and
    /// never leaves two loops racing.
    public func start() {
        runLoop?.cancel()
        runLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // If `stop()` cancels the loop while parked here, exit instead of running a trailing
                // `flush()` (on backgrounding the interval is still finite, so the guard alone wouldn't
                // catch it).
                do {
                    try await self.clock.sleep(self.flushInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.flush()
            }
        }
    }

    /// Cancels the run loop and every in-flight lane drain, then restores each lane's lease to
    /// `QueueStore` synchronously so it survives shutdown. Cancel-then-restore is safe against
    /// double-restore: a lane's drain task skips its own restore when it sees a cancelled task.
    public func stop() {
        runLoop?.cancel()
        runLoop = nil
        deadlineWake?.cancel()
        deadlineWake = nil
        let active = lanes
        for drain in active.values {
            drain.task.cancel()
        }
        lanes = [:]
        for (lane, drain) in active {
            restore(drain.batch, lane: lane)
        }
    }

    /// Immediate flush outside the timed cadence (high-priority path).
    public func flushNow() async {
        await flush()
    }

    public func networkConnectivityChanged(_ status: Reachability.NetworkStatus) {
        switch status {
        case .notReachable:
            flushInterval = .infinity
            stop()
        case .reachableViaWiFi:
            flushInterval = FlushConstants.wifiFlushInterval
            start()
        case .reachableViaWWAN:
            flushInterval = FlushConstants.cellularFlushInterval
            start()
        }
    }

    // MARK: - Flush

    /// Runs `willDrain`, then serves lanes round-robin: each eligible lane leases its batch and
    /// starts a per-lane drain task, and `flush()` awaits them all. See the type doc for the
    /// per-lane success/failure, concurrency, and bound behavior.
    private func flush() async {
        // Gate: pre-init or offline.
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else { return }
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Let the owner enqueue last-minute requests, then lease lane-by-lane (incl. those).
        await willDrain?()
        guard !Task.isCancelled else { return }

        for lane in laneSelection(limit: FlushConstants.maxLanesInFlight) {
            // Per-lane deadline gate: skip lanes whose backoff deadline is still in the future
            // (each lane gates on its own deadline, so one lane's wait never delays another
            // lane's sends).
            if case .wait = advanceBackoffGate(for: lane) {
                continue
            }

            let lease = QueueStore.shared.drain(lane: lane)
            guard !lease.isEmpty else { continue }
            // Send on a task OUTSIDE the actor: awaits in `sendHead` would otherwise re-enter the
            // actor mid-send and deadlock the pass. Each task awaits the actor only at its join
            // points (`laneHead`, `finishLane`), which run while no drain is mid-`await`.
            let task = Task { [self] in await drainLane(lane) }
            lanes[lane] = LaneDrain(batch: lease, task: task)
        }

        for drain in lanes.values {
            await drain.task.value
        }
        // Each lane task removes its own entry (finishLane / restoreLease) as it completes; by the
        // time all join, the active set is empty. Clear defensively so no stale entry lingers.
        lanes = [:]
        // Wake at the earliest outstanding lane deadline rather than waiting for the next periodic
        // tick, so a backed-off lane resumes AT its deadline (not up to one interval late).
        scheduleDeadlineWake()
    }

    /// Sends the heads of `lane`'s leased batch in FIFO order until the lane is drained or stops on
    /// a retryable failure. `stop()` may cancel the task mid-send; the restore is then owned by
    /// `stop()`, and the cancelled task skips its own restore so the batch is restored exactly once.
    private func drainLane(_ lane: RequestLane) async {
        while let head = laneHead(lane) {
            await sendHead(head, lane: lane)
            if Task.isCancelled {
                // `stop()` already restored the batch and cleared the active set; do NOT restore
                // again here (the batch would double-enqueue).
                return
            }
            if shouldStopLane(lane) {
                restoreLease(for: lane)
                return
            }
        }
        finishLane(lane)
    }

    /// The head of `lane`'s active batch, or `nil` when the lane is drained or no longer active.
    private func laneHead(_ lane: RequestLane) -> KlaviyoRequest? {
        lanes[lane]?.batch.first
    }

    /// Whether `lane` must stop after the last send: a retryable failure was recorded (its retry
    /// state advanced past the head's initial attempt, or a backoff is outstanding).
    private func shouldStopLane(_ lane: RequestLane) -> Bool {
        guard let state = laneRetryStates[lane] else { return false }
        switch state {
        case let .retry(count):
            return count != FlushConstants.initialAttempt
        case .retryWithBackoff:
            return true
        }
    }

    /// Marks a fully-drained lane as served for round-robin and resets its retry bookkeeping.
    private func finishLane(_ lane: RequestLane) {
        lastServedLaneIndex = RequestLane.allCases.firstIndex(of: lane)
        laneRetryStates[lane] = nil
        laneDeadlines[lane] = nil
        lanes[lane] = nil
    }

    /// Restores one lane's remaining batch to the front of that lane in the durable queue and
    /// clears the lane from the active set. `.synchronous`: the batch is in-memory only here, so it
    /// must hit disk before we return or a shutdown within a debounce window would drop it.
    private func restoreLease(for lane: RequestLane) {
        guard let drain = lanes[lane] else { return }
        lanes[lane] = nil
        restore(drain.batch, lane: lane)
    }

    /// Prepends `batch` to the front of `lane` in the durable store (no-op when empty). Centralized
    /// so `stop()` and `restoreLease(for:)` share the `.synchronous` durability contract.
    private func restore(_ batch: [KlaviyoRequest], lane: RequestLane) {
        guard !batch.isEmpty else { return }
        QueueStore.shared.prepend(batch, lane: lane, persist: .synchronous)
    }

    /// The lanes this pass serves: every lane with pending work (per a cheap store snapshot),
    /// ordered round-robin starting after the last lane served, capped at the global in-flight
    /// bound. Lanes whose only work arrived after the pass started (or that fall past the cap) are
    /// picked up on the next tick, so in flight never exceeds the bound.
    private func laneSelection(limit: Int) -> [RequestLane] {
        let snapshot = QueueStore.shared.requests
        var pending = RequestLane.allCases.filter { lane in
            snapshot.contains { $0.endpoint.lane == lane }
        }
        guard pending.count > 1, let lastServedLaneIndex,
              let lastInPending = pending.firstIndex(of: RequestLane.allCases[lastServedLaneIndex]) else {
            return Array(pending.prefix(limit))
        }
        // Rotate so the lane after the last-served one leads; the previously-served lane goes last.
        let start = pending.index(after: lastInPending) == pending.endIndex ? pending.startIndex
            : pending.index(after: lastInPending)
        pending = Array(pending[start...] + pending[..<start])
        return Array(pending.prefix(limit))
    }

    /// Sends the head of `lane`'s lease and applies the result. Runs OUTSIDE the actor (called from
    /// the lane's drain task) so the `await send` suspension doesn't re-enter the actor; all actor
    /// state is touched only at join points (`laneAttemptNumber`, `applySuccess`, and
    /// `handleSendFailure`). Other lanes are unaffected by this lane's outcome either way.
    private nonisolated func sendHead(_ head: KlaviyoRequest, lane: RequestLane) async {
        let numAttempts = await laneAttemptNumber(for: lane)

        let attemptInfo: RequestAttemptInfo
        do {
            attemptInfo = try RequestAttemptInfo(
                attemptNumber: numAttempts,
                maxAttempts: head.endpoint.maxRetries
            )
        } catch {
            environment.emitDeveloperWarning("Invalid RequestAttemptInfo parameters: \(error)")
            await restoreLease(for: lane)
            return
        }

        let outcome = await send(head, attemptInfo)
        // If `stop()` cancelled the drain mid-send, its batch was already restored; skip applying
        // the outcome so a completed request is never re-restored and a failed one never twice.
        guard !Task.isCancelled else { return }
        switch outcome {
        case .success:
            if case let .registerPushToken(_, payload) = head.endpoint {
                // Don't let an older in-flight register revert a newer token; only write when no token
                // is set or the stored one matches (mirrors `clearOptimisticPushToken`).
                let storedToken = IdentityStore.shared.pushToken?.pushToken
                if storedToken == nil || storedToken == payload.data.attributes.token {
                    IdentityStore.shared.updatePushToken(PushTokenData(payload))
                }
            }
            await applySuccess(lane: lane)

        case let .failure(error):
            await handleSendFailure(error, head: head, lane: lane)
        }
    }

    /// The attempt number for `lane`'s next send, sourced from `.retry(count)` ONLY. The deadline
    /// gate always promotes `.retryWithBackoff` to `.retry` before any send, so the lane's
    /// retryState is `.retry` here. Reading `.retryWithBackoff` is what caused the reverted
    /// `requestCount: 0` stall — do NOT.
    private func laneAttemptNumber(for lane: RequestLane) -> Int {
        if case let .retry(count) = laneRetryStates[lane] {
            return count
        }
        return FlushConstants.initialAttempt
    }

    /// Dequeues `lane`'s head after a successful send and resets the lane's retry bookkeeping.
    private func applySuccess(lane: RequestLane) {
        lanes[lane]?.batch.removeFirst()
        clearLaneBackoff(lane)
    }

    /// Resets a lane's retry bookkeeping and clears any outstanding backoff deadline.
    private func clearLaneBackoff(_ lane: RequestLane) {
        laneRetryStates[lane] = .retry(FlushConstants.initialAttempt)
        laneDeadlines[lane] = nil
    }

    /// Result of the per-lane backoff deadline gate: whether this lane should wait out an
    /// outstanding backoff or proceed to drain + send.
    private enum BackoffGate {
        case wait
        case proceed
    }

    /// Reports whether `lane`'s backoff deadline is still in the future (skip this pass) or has
    /// passed (promote to a plain retry and let the caller fall through to drain + send). Timing is
    /// exact against the injected clock — the lane becomes eligible AT its deadline, never one
    /// interval late (tick path) or early (a burst of immediate flushes) as the old
    /// interval-countdown gate could. The failing request stays durable in `QueueStore`, so it
    /// survives the wait.
    private func advanceBackoffGate(for lane: RequestLane) -> BackoffGate {
        guard case let .retryWithBackoff(requestCount, _, _) = laneRetryStates[lane],
              let deadline = laneDeadlines[lane] else {
            return .proceed
        }
        if clock.now() < deadline {
            return .wait
        }
        // Deadline passed: promote to a plain retry and clear the deadline.
        laneDeadlines[lane] = nil
        laneRetryStates[lane] = .retry(requestCount)
        return .proceed
    }

    /// (Re)schedules the one-shot wake at the earliest outstanding lane deadline, so a backed-off
    /// lane is retried at its deadline instead of on the next periodic tick. Cancels any previous
    /// wake (a new earlier deadline replaces it); a no-op while stopped (the run loop owns all
    /// flushing then; `start()`'s first tick reschedules). The wake calls `flush()` like a periodic
    /// tick — `flush()` is reentrant-guarded (`isFlushing`) and gated (api key / finite interval),
    /// so a wake that fires while stopped or mid-flush is harmless.
    private func scheduleDeadlineWake() {
        deadlineWake?.cancel()
        deadlineWake = nil
        guard runLoop != nil,
              let earliest = laneDeadlines.values.min() else { return }
        let delay = max(0, earliest.timeIntervalSince(clock.now()))
        deadlineWake = Task { [weak self] in
            do {
                try await self?.clock.sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Classifies a send failure and applies it to `lane` only: non-retryable → dequeue + keep
    /// draining the lane; retryable → set the lane's retry state, drop the head if past
    /// `maxRetries`, and leave the lane's lease for `drainLane` to restore (which stops THIS lane;
    /// other lanes still drain).
    private func handleSendFailure(_ error: KlaviyoAPIError, head: KlaviyoRequest,
                                   lane: RequestLane) {
        switch classifyFailure(error: error, retryState: laneRetryStates[lane]
            ?? .retry(FlushConstants.initialAttempt)) {
        case .dequeue:
            // Non-retryable: remove the head and keep sending the rest of the lane.
            // Parity: `deQueueCompletedResults` for a non-retryable failure.
            Self.clearOptimisticPushToken(head, error: error)
            lanes[lane]?.batch.removeFirst()
            clearLaneBackoff(lane)

        case let .clearInvalidFieldsAndDequeue(fields):
            // Clear the rejected field(s) on the
            // canonical store so the next request to the API won't carry a stale bad value.
            IdentityStore.shared.mutate { identity in
                for field in fields {
                    switch field {
                    case .email: identity.email = nil
                    case .phone: identity.phoneNumber = nil
                    }
                }
            }
            lanes[lane]?.batch.removeFirst()
            clearLaneBackoff(lane)

        case let .retry(newState):
            // Transient network error. Set the lane's retry state; if it exceeded `maxRetries`, drop
            // the head and reset the count (parity: `requestFailed`). `drainLane` sees the advanced
            // state via `shouldStopLane` and restores the lane's lease.
            laneRetryStates[lane] = newState
            laneDeadlines[lane] = nil
            if case let .retry(count) = newState,
               count > head.endpoint.maxRetries {
                Self.clearOptimisticPushToken(head, error: error)
                lanes[lane]?.batch.removeFirst()
                laneRetryStates[lane] = .retry(FlushConstants.initialAttempt)
            }

        case let .retryWithBackoff(newState):
            // Rate-limit / server error: convert the backoff into an absolute per-lane deadline
            // (value unchanged from the old countdown gate — only WHEN it fires changed); the
            // deadline gate waits it out, then resends. If past `maxRetries`, drop the head and
            // reset to `.retry(initialAttempt)`. The count is used raw as the attempt number, so the
            // reset must be `initialAttempt`, never `0` — `.retry(0)` is rejected by
            // `RequestAttemptInfo` → permanent stall.
            laneRetryStates[lane] = newState
            if case let .retryWithBackoff(requestCount, _, backoff) = newState,
               requestCount > head.endpoint.maxRetries {
                Self.clearOptimisticPushToken(head, error: error)
                lanes[lane]?.batch.removeFirst()
                clearLaneBackoff(lane)
            } else if case let .retryWithBackoff(_, _, backoff) = newState {
                // `backoff` arrives pre-composed by the network layer (Retry-After honoured,
                // exponential otherwise, jitter applied, exponential capped at 300s). Floor it at
                // one flush interval for the current network tier (10s Wi-Fi / 30s cellular),
                // matching the old gate where a sub-interval backoff still cost one tick. The
                // deadline itself is not re-capped: a server Retry-After above 300s stays honoured.
                let floor = FlushConstants.backoffFloor(forFlushInterval: flushInterval)
                let wait = max(TimeInterval(backoff), floor)
                laneDeadlines[lane] = clock.now().addingTimeInterval(wait)
            }
        }
    }

    /// Rolls back the optimistic `IdentityStore` push token when its `registerPushToken` is
    /// permanently dropped, so a later identical `setPushToken` re-enqueues rather than dedup-
    /// skipping a token that never registered. Guarded two ways:
    /// - Only when the stored token still matches the dropped request's token, so a newer token set
    ///   in the meantime is preserved.
    /// - Not on a server 4xx (`httpError`): Android parity keeps the token on a definitive rejection
    ///   rather than churning the same value back onto the queue.
    private nonisolated static func clearOptimisticPushToken(_ head: KlaviyoRequest,
                                                             error: KlaviyoAPIError) {
        if case .httpError = error {
            return
        }
        guard case let .registerPushToken(_, payload) = head.endpoint,
              IdentityStore.shared.pushToken?.pushToken == payload.data.attributes.token else { return }
        IdentityStore.shared.updatePushToken(nil)
    }
}
