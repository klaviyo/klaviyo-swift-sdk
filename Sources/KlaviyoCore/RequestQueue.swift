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
/// Failure classification and retry/backoff land in a later task.
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
    /// Re-entrancy guard. `flush()` suspends at `await willDrain?()` and `await send(...)`; actor
    /// isolation serializes synchronous access but does NOT prevent another `flush()` (e.g. the
    /// high-priority `flushNow()`) from entering across those suspension points. Without this guard a
    /// concurrent flush would re-run `drainAll()` (returning `[]`) and clobber the leased batch,
    /// dropping the in-flight requests from both memory and disk. Mirrors the reducer's
    /// `if state.flushing { return .none }`.
    private var isFlushing = false

    public init(clock: SleepClock,
                send: @escaping Send,
                willDrain: (@Sendable () async -> Void)? = nil) {
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
                try? await self.clock.sleep(self.flushInterval)
                await self.flush()
            }
        }
    }

    /// Cancels the run loop and restores any in-flight lease to `QueueStore` so requests leased for a
    /// flush survive shutdown. Parity with `cancelInFlightRequests` in the legacy reducer.
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

    // MARK: - Flush

    /// Drains `QueueStore.shared` and sends its requests sequentially through `send`. Mirrors the
    /// legacy reducer's `flushQueue` + `sendRequest` + `deQueueCompletedResults` success path:
    /// runs the `willDrain` seam so the owner can enqueue last-minute requests before the drain,
    /// leases the whole batch, and sends head-first in FIFO order. On `.success` a registered push
    /// token is written back to the canonical `IdentityStore`. Failure handling (classification,
    /// retry/backoff) lands in Task 5; for now a `.failure` stops the flush and restores the lease.
    private func flush() async {
        // 1. Gate: no apiKey means pre-init (flushing stays gated); a non-finite interval means the
        //    cadence is disabled. Either way there is nothing to flush.
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else { return }

        // 1b. Re-entrancy guard. Set/guard/clear are atomic w.r.t. other actor calls because the
        //     actor is non-reentrant BETWEEN suspension points; the `defer` clears the flag on every
        //     exit path (empty batch, throw, failure, normal completion).
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
            // Mirror the reducer's attempt-number sourcing: a `.retry(count)` supplies the count,
            // anything else falls back to the first attempt.
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

            switch await send(head, attemptInfo) {
            case .success:
                if case let .registerPushToken(_, payload) = head.endpoint {
                    IdentityStore.shared.updatePushToken(pushTokenData(from: payload))
                }
                requestsInFlight.removeFirst()
                retryState = .retry(FlushConstants.initialAttempt)

            case .failure:
                // Task 5: classify + retry/backoff. For now stop the flush and restore the lease.
                restoreLease()
                return
            }
        }
    }

    /// Restores the still-leased batch to the front of the durable queue and clears the in-memory
    /// lease. `.synchronous`: the lease is in-memory only and cleared here, so it must hit disk
    /// before we return or a shutdown within a debounce window would drop it. Parity with the
    /// reducer's `cancelInFlightRequests`.
    private func restoreLease() {
        guard !requestsInFlight.isEmpty else { return }
        QueueStore.shared.prepend(requestsInFlight, persist: .synchronous)
        requestsInFlight = []
    }

    /// Reconstructs a ``PushTokenData`` from a registered-push-token request payload so a successful
    /// registration can be written back to `IdentityStore`. Mirrors `deQueueCompletedResults`'
    /// `.registerPushToken` write-back block in `StateManagement.swift`.
    private func pushTokenData(from payload: PushTokenPayload) -> PushTokenData {
        let attributes = payload.data.attributes
        let enablement = PushEnablement(rawValue: attributes.enablementStatus) ?? .authorized
        let background = PushBackground(rawValue: attributes.backgroundStatus) ?? .available
        return PushTokenData(
            pushToken: attributes.token,
            pushEnablement: enablement,
            pushBackground: background,
            deviceData: attributes.deviceMetadata
        )
    }
}
