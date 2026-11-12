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
    private let backgroundTasks: BackgroundTaskRunner

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
    /// Last status applied by `networkConnectivityChanged`; `nil` until the first callback.
    private var lastNetworkStatus: Reachability.NetworkStatus?
    /// Set by a reconnect flush that found another flush running; that flush re-runs before returning.
    private var flushRequested = false
    /// The running flush body, so `stop()` and background expiry can cancel it.
    private var activeFlush: Task<Void, Never>?
    /// Which scope started `activeFlush` (0 = foreground loop). A scope's expiry only cancels a flush
    /// it owns, so a priority task expiring can't abort the main drain, and vice versa.
    private var activeFlushOwner = 0
    private var nextOwner = 0
    /// Priority scopes by owner, so a scope's own expiry cancels its wait and stops it starting a flush.
    private var priorityScopes: [Int: Task<Void, Never>] = [:]
    /// Bumped whenever a flush is abandoned. A flush whose generation no longer matches discards
    /// whatever its late-returning send reports instead of touching a newer lease.
    private var flushGeneration = 0
    /// Between `enterBackground()` and `start()`; reachability changes must not restart the loop.
    private var inBackground = false
    private var backgroundDrainTask: Task<Void, Never>?
    private var backgroundDrainId = 0

    public init(
        clock: SleepClock,
        send: @escaping Send,
        willDrain: (@Sendable () async -> Void)? = nil,
        backgroundTasks: BackgroundTaskRunner = .production
    ) {
        self.clock = clock
        self.send = send
        self.willDrain = willDrain
        self.backgroundTasks = backgroundTasks
    }

    // MARK: - Lifecycle

    /// (Re)starts the run loop. Any existing loop is cancelled first so `start()` is idempotent and
    /// never leaves two loops racing.
    public func start() {
        inBackground = false
        startLoop(flushImmediately: false)
    }

    /// `flushImmediately` skips the first sleep (used on reconnect).
    private func startLoop(flushImmediately: Bool) {
        runLoop?.cancel()
        runLoop = Task { [weak self] in
            var skipSleep = flushImmediately
            while !Task.isCancelled {
                guard let self else { return }
                if skipSleep {
                    skipSleep = false
                    await self.flush(retryIfBusy: true)
                    continue
                }
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

    /// Minimum retry delay: one flush interval, or the Wi-Fi interval while offline (infinite).
    private var retryFloor: TimeInterval {
        flushInterval.isFinite ? flushInterval : FlushConstants.wifiFlushInterval
    }

    /// How long the run loop sleeps: until the head's retry deadline, else one flush interval.
    private func nextDelay() -> TimeInterval {
        // Pre-init and offline flushes no-op, so a due head must not turn the loop into a busy spin.
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else {
            return flushInterval
        }
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
        abandonActiveFlush()
    }

    /// Cancels the running flush (if any), restores its lease and invalidates it, so a send that
    /// returns late is discarded. Does not wait on the network.
    private func abandonActiveFlush() {
        activeFlush?.cancel()
        activeFlush = nil
        flushGeneration += 1
        isFlushing = false
        restoreLease()
    }

    /// Immediate flush outside the timed cadence (high-priority path).
    public func flushNow() async {
        guard await !backgroundTasks.isAppActive() else {
            await flush(propagateCancellation: true)
            return
        }
        await priorityFlushInBackground()
    }

    /// High-priority flush while the app is backgrounded or inactive: its own task, its own expiry.
    private func priorityFlushInBackground() async {
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else { return }
        nextOwner += 1
        let owner = nextOwner
        let handle = await backgroundTasks.begin("com.klaviyo.priority-flush") { [weak self] in
            Task { await self?.expireFlush(owner: owner) }
        }
        let scope = Task {
            // A flush already running (e.g. the main drain) finishes first; the pass below then drains
            // everything queued by then, including this request.
            if let running = await self.activeFlush {
                let finished = await self.waitWithoutBlocking(
                    on: running, timeout: FlushConstants.backgroundSendTimeout
                )
                if !finished, !Task.isCancelled { await self.abandonActiveFlushIfNotOwnedBy(owner) }
            }
            if !Task.isCancelled {
                await self.flush(owner: owner, propagateCancellation: true)
            }
        }
        priorityScopes[owner] = scope
        await scope.value
        priorityScopes[owner] = nil
        handle?.end()
    }

    private func abandonActiveFlushIfNotOwnedBy(_ owner: Int) {
        if activeFlushOwner != owner { abandonActiveFlush() }
    }

    /// Scoped expiry: stop this scope's own waiting, and cancel the flush only if this scope started it.
    private func expireFlush(owner: Int) {
        priorityScopes[owner]?.cancel()
        if activeFlushOwner == owner { abandonActiveFlush() }
    }

    // MARK: - Background

    /// Stops the timed loop but leaves any flush in progress running, so a background drain can wait
    /// for it. `start()` (foreground) resumes the loop.
    public func enterBackground() {
        inBackground = true
        runLoop?.cancel()
        runLoop = nil
    }

    /// Drains the queue under a background task, serially, one 10s budget per request. Returns when the
    /// drain finishes or the task expires. Joins a drain already running. No-ops (and begins no task)
    /// when pre-init, offline, or there is nothing to send.
    public func backgroundDrain() async {
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else { return }
        if let running = backgroundDrainTask {
            await running.value
            return
        }
        guard activeFlush != nil || hasDueWork else { return }
        backgroundDrainId += 1
        let id = backgroundDrainId
        let task = Task { await self.runBackgroundDrain(id: id) }
        backgroundDrainTask = task
        await task.value
    }

    /// Something is queued and its head isn't waiting out its own backoff.
    private var hasDueWork: Bool {
        guard let head = QueueStore.shared.head else { return false }
        return !head.isAwaitingRetry(at: environment.date())
    }

    private func runBackgroundDrain(id: Int) async {
        nextOwner += 1
        let owner = nextOwner
        let handle = await backgroundTasks.begin("com.klaviyo.queue-flush") { [weak self] in
            // System expiry thread: only schedule the restore. The runner ends the task right after.
            Task { await self?.expireBackgroundDrain(owner: owner) }
        }
        if let running = activeFlush {
            // A foreground send has no budget of its own: bound the wait, then put it back and drain.
            let finished = await waitWithoutBlocking(
                on: running, timeout: FlushConstants.backgroundSendTimeout
            )
            if !finished, !Task.isCancelled { abandonActiveFlush() }
        }
        if !Task.isCancelled, hasDueWork {
            await flush(
                owner: owner,
                sendTimeout: FlushConstants.backgroundSendTimeout,
                propagateCancellation: true
            )
        }
        handle?.end()
        if backgroundDrainId == id { backgroundDrainTask = nil }
    }

    /// Background task expired: cancel the drain and put the lease back. The lease is already on disk,
    /// so this only tidies memory; it never waits on the network.
    private func expireBackgroundDrain(owner: Int) {
        backgroundDrainTask?.cancel()
        backgroundDrainTask = nil
        expireFlush(owner: owner)
    }

    /// Waits for `task`, returning `false` if `timeout` elapses first and `true` if it finished.
    /// Also returns at once if the caller is cancelled (a send may ignore cancellation).
    private func waitWithoutBlocking(on task: Task<Void, Never>, timeout: TimeInterval) async -> Bool {
        let race = OneShot<Bool>()
        let clock = clock
        let waiter = Task {
            await task.value
            race.finish(true)
        }
        let timer = Task {
            do {
                try await clock.sleep(timeout)
                race.finish(false)
            } catch {}
        }
        let finished = await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            race.finish(false)
        }
        waiter.cancel()
        timer.cancel()
        return finished
    }

    private func interval(for status: Reachability.NetworkStatus) -> TimeInterval {
        switch status {
        case .notReachable: return .infinity
        case .reachableViaWiFi: return FlushConstants.wifiFlushInterval
        case .reachableViaWWAN: return FlushConstants.cellularFlushInterval
        }
    }

    public func networkConnectivityChanged(_ status: Reachability.NetworkStatus) {
        // Reachability flags can change while the status stays the same; only real transitions act.
        guard status != lastNetworkStatus else { return }
        lastNetworkStatus = status
        if inBackground {
            // No loop while backgrounded: record the state, then let the foreground `start()` resume.
            flushInterval = interval(for: status)
            if status == .notReachable { stop() } else { clearBackoffs() }
            return
        }
        switch status {
        case .notReachable:
            flushInterval = .infinity
            stop()
        case .reachableViaWiFi:
            flushInterval = FlushConstants.wifiFlushInterval
            clearBackoffs()
            startLoop(flushImmediately: true)
        case .reachableViaWWAN:
            flushInterval = FlushConstants.cellularFlushInterval
            clearBackoffs()
            startLoop(flushImmediately: true)
        }
    }

    /// Drops pending backoff on queued and leased entries, keeping `attempts`.
    private func clearBackoffs() {
        QueueStore.shared.clearBackoffs()
        for index in requestsInFlight.indices {
            requestsInFlight[index].clearBackoff()
        }
    }

    // MARK: - Flush

    /// Runs `willDrain`, leases the whole `QueueStore` batch, and sends head-first (FIFO). See the
    /// type doc for the success/failure handling.
    ///
    /// The body runs in its own task so cancelling the run loop never cancels an in-flight send;
    /// only `stop()` and background expiry do. `propagateCancellation` ties it to the caller instead.
    /// `sendTimeout` bounds each send (background drain); `nil` leaves the session's own timeout.
    private func flush(
        owner: Int = 0,
        retryIfBusy: Bool = false,
        sendTimeout: TimeInterval? = nil,
        propagateCancellation: Bool = false
    ) async {
        // Gate: pre-init or offline.
        guard SDKConfigStore.shared.current.apiKey != nil, flushInterval.isFinite else { return }
        guard !isFlushing else {
            flushRequested = flushRequested || retryIfBusy
            return
        }
        isFlushing = true
        flushRequested = false
        let generation = flushGeneration
        let task = Task { await self.runFlush(generation: generation, sendTimeout: sendTimeout) }
        activeFlush = task
        activeFlushOwner = owner
        if propagateCancellation {
            await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        } else {
            await task.value
        }
    }

    private func runFlush(generation: Int, sendTimeout: TimeInterval?) async {
        await drainAndSend(generation: generation, sendTimeout: sendTimeout)
        // Abandoned (stop or expiry): the new owner of the flag is not this stale flush.
        guard generation == flushGeneration else { return }
        isFlushing = false
        activeFlush = nil
        // A reconnect landed mid-flush: restart the loop so its immediate flush runs on a live task.
        // No restart if still stopped or offline.
        if flushRequested, flushInterval.isFinite, runLoop != nil {
            startLoop(flushImmediately: true)
        }
    }

    private func drainAndSend(generation: Int, sendTimeout: TimeInterval?) async {
        // Cheap pre-check: skip the drain + restore round trip while the head waits out its own
        // backoff. The per-head check in the send loop is the authoritative gate. The run loop
        // sleeps until the head's deadline, so a due retry flushes without waiting a full tick.
        if QueueStore.shared.head?.isAwaitingRetry(at: environment.date()) == true {
            return
        }

        // Let the owner enqueue last-minute requests, then lease everything (incl. those).
        await willDrain?()
        guard !Task.isCancelled, generation == flushGeneration else { return }
        requestsInFlight = QueueStore.shared.drainAll()
        guard !requestsInFlight.isEmpty else { return }

        while let head = requestsInFlight.first {
            guard generation == flushGeneration else { return }
            // Serial queue: a head still inside its own backoff blocks the rest (Android parity:
            // `PendingRetry` breaks the serial send). Only the head's own state gates it, so a
            // request front-inserted ahead of a backing-off one sends at once.
            if head.isAwaitingRetry(at: environment.date()) {
                restoreLease()
                return
            }
            switch await sendHead(head, generation: generation, sendTimeout: sendTimeout) {
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
    private func sendHead(
        _ head: QueuedRequest,
        generation: Int,
        sendTimeout: TimeInterval?
    ) async -> FailureOutcome {
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

        let result: Result<Data, KlaviyoAPIError>?
        if let sendTimeout {
            result = await sendWithBudget(head.request, attemptInfo, timeout: sendTimeout)
        } else {
            result = await send(head.request, attemptInfo)
        }
        // Stale: this flush was abandoned (stop or expiry) while the send was out; drop its result.
        guard generation == flushGeneration, !requestsInFlight.isEmpty else { return .stopFlush }
        guard let outcome = result else {
            // Budget spent or cancelled, not a server answer.
            return Task.isCancelled ? abandonCurrentAttempt() : putBackStalledHead()
        }
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
            completeHead()
            return .continueSending

        case let .failure(error):
            // A send cancelled under us can surface as any error (e.g. `CancellationError`, which
            // classifies as a drop). Never treat it as a failed attempt.
            if Task.isCancelled { return abandonCurrentAttempt() }
            return handleSendFailure(error, head: head)
        }
    }

    /// Races one send against `timeout`. Returns `nil` on timeout or cancellation without waiting on
    /// the send, which on iOS 13/14 can ignore cancellation and return late.
    private func sendWithBudget(
        _ request: KlaviyoRequest,
        _ info: RequestAttemptInfo,
        timeout: TimeInterval
    ) async -> Result<Data, KlaviyoAPIError>? {
        let race = OneShot<Result<Data, KlaviyoAPIError>?>()
        let send = send
        let clock = clock
        let sendTask = Task { await race.finish(send(request, info)) }
        let timer = Task {
            do {
                try await clock.sleep(timeout)
                guard !Task.isCancelled else { return }
                race.finish(nil)
            } catch {}
        }
        let result = await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            race.finish(nil)
        }
        timer.cancel()
        if result == nil { sendTask.cancel() }
        return result
    }

    /// The head stalled past its budget: return it to the durable queue untouched (no attempt, no
    /// backoff) and keep draining the rest of the lease.
    private func putBackStalledHead() -> FailureOutcome {
        let stalled = requestsInFlight.removeFirst()
        QueueStore.shared.prepend([stalled], persist: .synchronous)
        return .continueSending
    }

    /// Cancelled, not failed: no attempt recorded. A head with a due deadline waits one floor
    /// interval so a repeatable cancel can't hot-loop.
    private func abandonCurrentAttempt() -> FailureOutcome {
        requestsInFlight[0].deferRetry(by: retryFloor, now: environment.date())
        if #available(iOS 14.0, *) {
            Logger.networking.debug("Send cancelled; restoring request without recording an attempt")
        }
        restoreLease()
        return .stopFlush
    }

    /// Removes the head from the lease and from disk (synchronous), so it is never re-sent after a kill.
    private func completeHead() {
        let done = requestsInFlight.removeFirst()
        QueueStore.shared.complete(id: done.id)
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
            completeHead()
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
            completeHead()
            return .continueSending

        case .abandonAttempt:
            return abandonCurrentAttempt()

        case let .retry(backoff):
            // Transport, rate-limit or server error: the backoff and attempt count belong to this
            // request alone. Drop it once it exhausts its own `maxRetries` (parity: `requestFailed`).
            // Floor the delay at one flush interval (finite fallback when offline).
            var failed = head
            failed.recordRetryableFailure(
                retryAfter: max(backoff, Int(retryFloor.rounded(.up))),
                now: environment.date()
            )
            if failed.hasExhaustedRetries {
                clearOptimisticPushToken(head.request, error: error)
                completeHead()
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
