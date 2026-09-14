//
//  RequestQueue.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

/// Core-owned flush engine: drains `QueueStore.shared` on a timed cadence and sends through an
/// injected transport. `flush()` leases the pending batch and sends it head-first (FIFO), writing a
/// registered push token back to `IdentityStore` on success. On failure it classifies the error and
/// either dequeues + continues (non-retryable), restores the lease and stops so retries resume next
/// tick (transient), or records a durable countdown backoff and restores the request so the
/// countdown gate in `flush()` waits it out over ticks before resending (rate-limit / server error).
public actor RequestQueue {
    /// Transport seam: sends one request with its per-attempt retry metadata and reports the result.
    public typealias Send = @Sendable (KlaviyoRequest, RequestAttemptInfo)
        async -> Result<Data, KlaviyoAPIError>

    // MARK: - Injected dependencies

    private let clock: SleepClock
    private let send: Send
    /// Optional hook invoked before each drain; wired at bootstrap to
    /// `ProfilePropertyBuffer.flushIntoQueue` so staged profile properties fold in before the drain.
    private let willDrain: (@Sendable () async -> Void)?

    // MARK: - Owned state

    /// Requests leased out of `QueueStore` for the current flush. Restored to the store on `stop()`
    /// so a shutdown mid-flush never drops them.
    private var requestsInFlight: [KlaviyoRequest] = []
    /// Current cadence between flushes. Defaults to the wifi interval; adjusted by
    /// `networkConnectivityChanged` (wifi/cellular interval, or `.infinity` when offline).
    private var flushInterval: TimeInterval = FlushConstants.wifiFlushInterval
    /// Retry bookkeeping for the request currently being sent.
    private var retryState: RetryState = .retry(FlushConstants.initialAttempt)
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

    /// Cancels the run loop and restores any in-flight lease to `QueueStore` so it survives shutdown.
    ///
    /// NOTE: `stop()`/`restoreLease()` use `QueueStore.prepend`, which (unlike `QueueStore.restore`)
    /// does NOT dedup by id. Safe only because exactly one path owns the lease at a time — drained
    /// once, restored once — so no id can be re-inserted while still present in the store.
    public func stop() {
        runLoop?.cancel()
        runLoop = nil
        if !requestsInFlight.isEmpty {
            QueueStore.shared.prepend(requestsInFlight, persist: .synchronous)
            requestsInFlight = []
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

    /// Runs `willDrain`, leases the whole `QueueStore` batch, and sends head-first (FIFO). See the
    /// type doc for the success/failure handling.
    private func flush() async {
        // Gate: pre-init or offline.
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else { return }
        // Reentrancy guard: a `flushNow()` must not interleave with an in-progress flush.
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Advance the durable countdown backoff once per flush; skip while one is outstanding (the
        // failing request stays durable in `QueueStore` during the wait). See `advanceBackoffGate`.
        if case .wait = advanceBackoffGate() { return }

        // Let the owner enqueue last-minute requests, then lease everything (incl. those).
        await willDrain?()
        guard !Task.isCancelled else { return }
        requestsInFlight = QueueStore.shared.drainAll()
        guard !requestsInFlight.isEmpty else { return }

        while let head = requestsInFlight.first {
            switch await sendHead(head) {
            case .continueSending:
                continue
            case .stopFlush:
                return
            }
        }
    }

    /// Sends the head request and applies the result, reporting whether the flush loop should
    /// continue or stop. Stops early if the attempt metadata is invalid or the lease was cleared
    /// mid-send (e.g. by `stop()`).
    private func sendHead(_ head: KlaviyoRequest) async -> FailureOutcome {
        // Source `numAttempts` from `.retry(count)` ONLY. The countdown gate always promotes
        // `.retryWithBackoff` to `.retry` before any send, so retryState is `.retry` here. Reading
        // `.retryWithBackoff` is what caused the reverted `requestCount: 0` stall — do NOT.
        var numAttempts = FlushConstants.initialAttempt
        if case let .retry(count) = retryState {
            numAttempts = count
        }

        let attemptInfo: RequestAttemptInfo
        do {
            attemptInfo = try RequestAttemptInfo(
                attemptNumber: numAttempts,
                maxAttempts: head.endpoint.maxRetries
            )
        } catch {
            environment.emitDeveloperWarning("Invalid RequestAttemptInfo parameters: \(error)")
            restoreLease()
            return .stopFlush
        }

        let outcome = await send(head, attemptInfo)
        guard !requestsInFlight.isEmpty else { return .stopFlush }
        switch outcome {
        case .success:
            if case let .registerPushToken(_, payload) = head.endpoint {
                IdentityStore.shared.updatePushToken(PushTokenData(payload))
            }
            requestsInFlight.removeFirst()
            retryState = .retry(FlushConstants.initialAttempt)
            return .continueSending

        case let .failure(error):
            return await handleSendFailure(error, head: head)
        }
    }

    /// Restores the still-leased batch to the front of the durable queue and clears the in-memory
    /// lease. `.synchronous`: the lease is in-memory only and cleared here, so it must hit disk
    /// before we return or a shutdown within a debounce window would drop it.
    private func restoreLease() {
        guard !requestsInFlight.isEmpty else { return }
        QueueStore.shared.prepend(requestsInFlight, persist: .synchronous)
        requestsInFlight = []
    }

    /// Result of the durable countdown backoff gate: whether this flush should wait out an
    /// outstanding backoff or proceed to drain + send.
    private enum BackoffGate {
        case wait
        case proceed
    }

    /// Advances the durable countdown backoff by one flush interval and reports whether `flush()`
    /// should skip this pass. Called once per flush (tick OR `flushNow()`), mirroring the reducer's
    /// `flushQueue`, which decremented on every dispatch. Timing is therefore approximate — a backoff
    /// can fire one interval late (tick path) or expire early (a burst of immediate flushes); that
    /// imprecision is the accepted cost of reducer parity. The failing request stays durable in
    /// `QueueStore`, so it survives the wait.
    private func advanceBackoffGate() -> BackoffGate {
        guard case let .retryWithBackoff(requestCount, totalCount, backoff) = retryState else {
            return .proceed
        }
        let remaining = max(backoff - Int(flushInterval), 0)
        if remaining > 0 {
            retryState = .retryWithBackoff(requestCount: requestCount,
                                           totalRetryCount: totalCount,
                                           currentBackoff: remaining)
            return .wait
        }
        // Expired: promote to a plain retry and let the caller fall through to drain + send.
        retryState = .retry(requestCount)
        return .proceed
    }

    /// Whether the flush loop should keep sending the next request or stop (and let the run loop
    /// retry on a later tick) after a send failure.
    private enum FailureOutcome {
        case continueSending
        case stopFlush
    }

    /// Classifies a send failure and applies it. Mirrors `handleRequestError` +
    /// `requestFailed`/`deQueueCompletedResults` in the legacy reducer: non-retryable → dequeue +
    /// CONTINUE; retryable → set `retryState`, drop the head if past `maxRetries`, then STOP.
    private func handleSendFailure(_ error: KlaviyoAPIError, head: KlaviyoRequest) async -> FailureOutcome {
        switch classifyFailure(error: error, retryState: retryState) {
        case .dequeue:
            // Non-retryable: remove the head and keep sending the rest of the batch.
            // Parity: `deQueueCompletedResults` for a non-retryable failure.
            requestsInFlight.removeFirst()
            retryState = .retry(FlushConstants.initialAttempt)
            return .continueSending

        case let .clearInvalidFieldsAndDequeue(fields):
            // Mirror `resetStateAndDequeue` in the reducer: nil the rejected field(s) on the
            // canonical store so the next request to the API won't carry a stale bad value.
            IdentityStore.shared.mutate { identity in
                for field in fields {
                    switch field {
                    case .email: identity.email = nil
                    case .phone: identity.phoneNumber = nil
                    }
                }
            }
            requestsInFlight.removeFirst()
            retryState = .retry(FlushConstants.initialAttempt)
            return .continueSending

        case let .retry(newState):
            // Transient network error. Set the new retry state; if it exceeded `maxRetries`, drop
            // the head and reset the count (parity: `requestFailed`).
            retryState = newState
            if case let .retry(count) = newState,
               count > head.endpoint.maxRetries {
                requestsInFlight.removeFirst()
                retryState = .retry(FlushConstants.initialAttempt)
            }
            // STOP: restore the remaining lease; retries resume on the next flush tick.
            restoreLease()
            return .stopFlush

        case let .retryWithBackoff(newState):
            // Rate-limit / server error. Record the backoff; the countdown gate waits it out then
            // resends. If past `maxRetries`, drop the head and reset to `.retry(initialAttempt)`.
            // This DELIBERATELY diverges from the reducer's `.retryWithBackoff(requestCount: 0)`
            // reset — under the countdown gate that promotes to `.retry(0)`, which
            // `RequestAttemptInfo` rejects → a permanent stall. Do NOT restore that parity.
            retryState = newState
            if case let .retryWithBackoff(requestCount, _, _) = newState,
               requestCount > head.endpoint.maxRetries {
                requestsInFlight.removeFirst()
                retryState = .retry(FlushConstants.initialAttempt)
            }
            restoreLease()
            return .stopFlush
        }
    }
}
