//
//  RequestQueue.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation
import OSLog

/// Core-owned flush engine: drains `QueueStore.shared` on a timed cadence and sends through an
/// injected transport. `flush()` leases the pending batch and sends it head-first (FIFO), writing a
/// registered push token back to `IdentityStore` on success. On failure it classifies the error and
/// either dequeues + continues (non-retryable), or records the failure on that request's own
/// `QueuedRequest` entry (`attempts` + wall-clock `nextAttemptAt`) and restores the lease, so the
/// head waits out its own backoff before resending (transport, rate-limit or server error).
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
    private var requestsInFlight: [QueuedRequest] = []
    /// Current cadence between flushes. Defaults to the wifi interval; adjusted by
    /// `networkConnectivityChanged` (wifi/cellular interval, or `.infinity` when offline).
    private var flushInterval: TimeInterval = FlushConstants.wifiFlushInterval
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
                    try await self.clock.sleep(self.nextDelay())
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.flush()
            }
        }
    }

    /// How long the run loop sleeps: until the head's retry deadline, else one flush interval.
    private func nextDelay() -> TimeInterval {
        // Pre-init flushes no-op, so a due head must not turn the loop into a busy spin.
        guard SDKConfigStore.shared.current.apiKey != nil else { return flushInterval }
        return nextFlushDelay(
            head: QueueStore.shared.head,
            now: environment.date(),
            flushInterval: flushInterval
        )
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
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Cheap pre-check: skip the drain + restore round trip while the head waits out its own
        // backoff. The per-head check in the send loop is the authoritative gate. The run loop
        // sleeps until the head's deadline, so a due retry flushes without waiting a full tick.
        if QueueStore.shared.head?.isAwaitingRetry(at: environment.date()) == true {
            return
        }

        // Let the owner enqueue last-minute requests, then lease everything (incl. those).
        await willDrain?()
        guard !Task.isCancelled else { return }
        requestsInFlight = QueueStore.shared.drainAll()
        guard !requestsInFlight.isEmpty else { return }

        while let head = requestsInFlight.first {
            // Serial queue: a head still inside its own backoff blocks the rest (Android parity:
            // `PendingRetry` breaks the serial send). Only the head's own state gates it, so a
            // request front-inserted ahead of a backing-off one sends at once.
            if head.isAwaitingRetry(at: environment.date()) {
                restoreLease()
                return
            }
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
    private func sendHead(_ head: QueuedRequest) async -> FailureOutcome {
        let attemptInfo: RequestAttemptInfo
        do {
            attemptInfo = try RequestAttemptInfo(
                attemptNumber: head.nextAttemptNumber,
                maxAttempts: head.request.endpoint.maxRetries
            )
        } catch {
            environment.emitDeveloperWarning("Invalid RequestAttemptInfo parameters: \(error)")
            restoreLease()
            return .stopFlush
        }

        let outcome = await send(head.request, attemptInfo)
        guard !requestsInFlight.isEmpty else { return .stopFlush }
        switch outcome {
        case .success:
            if case let .registerPushToken(_, payload) = head.request.endpoint {
                // Don't let an older in-flight register revert a newer token; only write when no token
                // is set or the stored one matches (mirrors `clearOptimisticPushToken`).
                let storedToken = IdentityStore.shared.pushToken?.pushToken
                if storedToken == nil || storedToken == payload.data.attributes.token {
                    IdentityStore.shared.updatePushToken(PushTokenData(payload))
                }
            }
            requestsInFlight.removeFirst()
            return .continueSending

        case let .failure(error):
            return handleSendFailure(error, head: head)
        }
    }

    /// Restores the still-leased batch, retry state included, to the front of the durable queue and
    /// clears the in-memory lease. `.synchronous`: the lease is in-memory only and cleared here, so
    /// it must hit disk before we return or a shutdown within a debounce window would drop it.
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

    /// Classifies a send failure and applies it: non-retryable → dequeue + CONTINUE; retryable →
    /// record the failure on the head's own entry, drop it if that exhausts its attempts, then STOP.
    private func handleSendFailure(_ error: KlaviyoAPIError, head: QueuedRequest) -> FailureOutcome {
        switch classifyFailure(error: error, attemptNumber: head.nextAttemptNumber) {
        case .dequeue:
            // Non-retryable: remove the head and keep sending the rest of the batch.
            // Parity: `deQueueCompletedResults` for a non-retryable failure.
            clearOptimisticPushToken(head.request, error: error)
            requestsInFlight.removeFirst()
            return .continueSending

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
            requestsInFlight.removeFirst()
            return .continueSending

        case .abandonAttempt:
            // Cancelled, not failed: keep the lease as-is with no attempt or backoff recorded.
            if #available(iOS 14.0, *) {
                Logger.networking.debug("Send cancelled; restoring request without recording an attempt")
            }
            restoreLease()
            return .stopFlush

        case let .retry(backoff):
            // Transport, rate-limit or server error: the backoff and attempt count belong to this
            // request alone. Drop it once it exhausts its own `maxRetries` (parity: `requestFailed`).
            // Floor the delay at one flush interval (finite fallback when offline).
            let floor = flushInterval.isFinite ? flushInterval : FlushConstants.wifiFlushInterval
            var failed = head
            failed.recordRetryableFailure(
                retryAfter: max(backoff, Int(floor.rounded(.up))),
                now: environment.date()
            )
            if failed.hasExhaustedRetries {
                clearOptimisticPushToken(head.request, error: error)
                requestsInFlight.removeFirst()
            } else {
                requestsInFlight[0] = failed
            }
            // STOP: restore the remaining lease; retries resume on a later flush.
            restoreLease()
            return .stopFlush
        }
    }

    /// Rolls back the optimistic `IdentityStore` push token when its `registerPushToken` is
    /// permanently dropped, so a later identical `setPushToken` re-enqueues rather than dedup-
    /// skipping a token that never registered. Guarded two ways:
    /// - Only when the stored token still matches the dropped request's token, so a newer token set
    ///   in the meantime is preserved.
    /// - Not on a server 4xx (`httpError`): Android parity keeps the token on a definitive rejection
    ///   rather than churning the same value back onto the queue.
    private func clearOptimisticPushToken(_ head: KlaviyoRequest, error: KlaviyoAPIError) {
        if case .httpError = error { return }
        guard case let .registerPushToken(_, payload) = head.endpoint,
              IdentityStore.shared.pushToken?.pushToken == payload.data.attributes.token else { return }
        IdentityStore.shared.updatePushToken(nil)
    }
}
