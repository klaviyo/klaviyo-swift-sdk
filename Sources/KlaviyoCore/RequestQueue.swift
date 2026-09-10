//
//  RequestQueue.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/10/26.
//

import Foundation

/// Core-owned flush engine that drains `QueueStore.shared` on a timed cadence and sends requests
/// through an injected transport. This is the skeleton: owned state, lifecycle (`start`/`stop`), and
/// the run loop. The real drain/send/retry logic lands in a later task; `flush()` is a no-op stub
/// here so the loop's timing is testable in isolation.
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

    /// Drains and sends pending requests.
    // filled in Task 4
    private func flush() async {
        // No-op stub; real drain/send/retry logic lands in Task 4.
    }
}
