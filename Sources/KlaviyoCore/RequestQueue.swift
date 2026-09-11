//
//  RequestQueue.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

/// Core-owned flush engine that drains `QueueStore.shared` on a timed cadence and sends requests
/// through an injected transport. Owns its state and lifecycle (`start`/`stop`), runs the timed run
/// loop, and implements the drain/send happy path: `flush()` leases the pending batch and sends it
/// head-first in FIFO order, writing a registered push token back to `IdentityStore` on success.
/// On failure it classifies the error and either dequeues + continues (non-retryable), stops and
/// restores the lease so retries resume next tick (transient), or sleeps the backoff and retries
/// the same head in place (rate-limit / server error).
public actor RequestQueue {
    /// Transport seam: sends one request with its per-attempt retry metadata and reports the result.
    public typealias Send = @Sendable (KlaviyoRequest, RequestAttemptInfo)
        async -> Result<Data, KlaviyoAPIError>

    // MARK: - Injected dependencies

    private let clock: SleepClock
    private let send: Send
    /// Optional hook invoked before each drain; wired by a later task.
    private let willDrain: (@Sendable () async -> Void)?

    // MARK: - Owned state

    /// Requests leased out of `QueueStore` for the current flush. Restored to the store on `stop()`
    /// so a shutdown mid-flush never drops them.
    private var requestsInFlight: [KlaviyoRequest] = []
    /// Current cadence between flushes. Defaults to the wifi interval; adjusted by a later task.
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
                // If `stop()` cancels the loop while it is parked here, exit instead of running a
                // trailing `flush()` — otherwise a cancelled idle wait would still drain+send (and
                // on backgrounding the interval is still finite, so the guard wouldn't catch it).
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

    /// Cancels the run loop and restores any in-flight lease to `QueueStore` so requests leased for a
    /// flush survive shutdown. Parity with `cancelInFlightRequests` in the legacy reducer.
    ///
    /// NOTE: `stop()`/`restoreLease()` use `QueueStore.prepend`, which (unlike `QueueStore.restore`)
    /// does NOT dedup by id. That is safe today only because exactly one path owns the in-flight
    /// lease at a time — the lease is drained once and restored once, so no id can be re-inserted
    /// while it is still present in the store.
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

    /// Drains `QueueStore.shared` and sends its requests sequentially through `send`.
    /// Runs the `willDrain` seam so the owner can enqueue last-minute requests before the drain,
    /// leases the whole batch, and sends head-first in FIFO order. On `.success` a registered push
    /// token is written back to the canonical `IdentityStore`. On `.failure` the error is classified
    /// (`classifyFailure`) and handled: non-retryable → dequeue + continue; transient → stop + lease
    /// restore (retries next tick); rate-limit/server → direct-sleep backoff then retry in place.
    private func flush() async {
        // 1. Gate: pre-init or offline. Do not flush.
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else { return }
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // 2. Let the owner enqueue any last-minute requests before we take the snapshot.
        await willDrain?()

        // 3. Lease the whole pending batch. Anything enqueued by `willDrain` above is already in the
        //    store, so it is included in this drain.
        requestsInFlight = QueueStore.shared.drainAll()
        guard !requestsInFlight.isEmpty else { return }

        // 4. Send head-first, FIFO, dequeuing each on success.
        while let head = requestsInFlight.first {
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
                return
            }

            let outcome = await send(head, attemptInfo)
            guard !requestsInFlight.isEmpty else { return }
            switch outcome {
            case .success:
                if case let .registerPushToken(_, payload) = head.endpoint {
                    IdentityStore.shared.updatePushToken(PushTokenData(payload))
                }
                requestsInFlight.removeFirst()
                retryState = .retry(FlushConstants.initialAttempt)

            case let .failure(error):
                switch await handleSendFailure(error, head: head) {
                case .continueSending:
                    continue
                case .stopFlush:
                    return
                }
            }
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

    /// Whether the flush loop should keep sending the next request or stop (and let the run loop
    /// retry on a later tick) after a send failure.
    private enum FailureOutcome {
        case continueSending
        case stopFlush
    }

    /// Classifies a send failure and applies it, returning whether `flush()` should continue with
    /// the next request or stop. Extracted from `flush()`. Mirrors `handleRequestError` +
    /// `requestFailed`/`deQueueCompletedResults` in the legacy reducer: non-retryable errors dequeue
    /// the head and CONTINUE; retryable errors set `retryState`, drop the head if it exceeded
    /// `maxRetries`, then STOP (network) or SLEEP + retry-in-place (backoff).
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
            // NOTE: read-modify-write is a TOCTOU vs any other IdentityStore writer. Safe here
            // only because the actor is unwired in this PR. The request-queue cutover must make
            // IdentityStore concurrent-writer-safe and give it an atomic field-clear; see
            // IdentityStore's SINGLE WRITER note.
            var identity = IdentityStore.shared.current
            for field in fields {
                switch field {
                case .email: identity.email = nil
                case .phone: identity.phoneNumber = nil
                }
            }
            IdentityStore.shared.update(identity)
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

        case let .retryWithBackoff(newState, seconds):
            // Rate-limit / server error. Set the new retry state; if it exceeded `maxRetries`, drop
            // the head, reset per `requestFailed`, and STOP.
            retryState = newState
            if case let .retryWithBackoff(requestCount, totalCount, backOff) = newState,
               requestCount > head.endpoint.maxRetries {
                requestsInFlight.removeFirst()
                retryState = .retryWithBackoff(
                    requestCount: 0,
                    totalRetryCount: totalCount,
                    currentBackoff: backOff
                )
                restoreLease()
                return .stopFlush
            }
            // Decision 2: sleep the backoff directly, then retry the SAME head in place (rather than
            // restoring + waiting for the reducer's per-tick countdown). The `isFlushing` guard
            // stays true across the sleep, so no concurrent flush runs.
            try? await clock.sleep(Double(seconds))
            // Promote back to `.retry(requestCount)` so the in-place retry advances `attemptNumber`
            // (parity with the reducer's backoff-expiry: `state.retryState = .retry(requestCount)`).
            // Without this the retried send would keep sourcing `numAttempts` as the initial attempt.
            if case let .retryWithBackoff(requestCount, _, _) = retryState {
                retryState = .retry(requestCount)
            }
            return .continueSending
        }
    }
}
