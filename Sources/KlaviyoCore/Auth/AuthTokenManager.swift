//
//  AuthTokenManager.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Combine
import Foundation
import OSLog

/// Owns the host-supplied ``AuthTokenProvider`` and serves the current auth JWT
/// to internal SDK consumers (in-app forms today, future feature modules
/// tomorrow).
///
/// Validates each token via ``JWTParser`` on acquisition, caches the result in
/// memory, and serves the cached string until either the cached token's `exp`
/// has elapsed (with the same clock-skew leeway ``JWTParser`` uses) or the
/// provider is replaced via ``registerProvider(_:)``.
///
/// Concurrent callers requesting a token while a fetch is in flight share the
/// result of that fetch — they do not trigger additional provider invocations.
/// Each caller bounds *its own* wait via ``FetchMode``; the underlying fetch
/// task is unaffected by individual callers timing out and continues until it
/// completes naturally (or until ``registerProvider(_:)`` cancels it).
///
/// The token cache is in-memory only — never persisted to disk or Keychain.
package actor AuthTokenManager {
    /// Latency budget for callers awaiting a token, expressed as a named policy
    /// rather than a free `TimeInterval` so the two budgets stay
    /// single-source-of-truth and can be tuned together based on production
    /// telemetry.
    package enum FetchMode: TimeInterval {
        /// 500ms budget. Used at form-display time, where a user is waiting on
        /// the form to appear — missing the personalization window is preferable
        /// to delaying the form.
        case interactive = 0.5

        /// 5s budget. Used by background acquisition paths (eager fetch at
        /// registration, scheduled refresh) where no user is actively waiting.
        case background = 5.0
    }

    /// Shared instance used by `KlaviyoSDK` and other SDK modules. Tests should
    /// construct their own instances to keep test runs independent.
    package static let shared = AuthTokenManager()

    /// Most recently validated token, if any. Cleared whenever
    /// ``registerProvider(_:)`` runs.
    private var cachedToken: ValidatedToken?

    /// Host-supplied closure that returns a fresh JWT on each invocation.
    /// Starts `nil`; set by ``registerProvider(_:)``.
    private var provider: AuthTokenProvider?

    /// In-flight fetch slot: a token-fetch task paired with the generation `id`
    /// that names it. Concurrent callers `await` the `task` rather than starting
    /// their own fetch. The `id` lets the fetch task itself decide whether to
    /// clear the slot on completion — a stale (cancelled) task waking up after
    /// a newer fetch was installed must not clobber the newer slot.
    ///
    /// Always set and cleared as a unit: there is no valid state where the
    /// task is present without its id, or vice versa.
    private var inFlight: (id: UUID, task: Task<String, Error>)?

    /// Sleep-and-refresh task that fires at ``refreshAtWallClock``. Cancelled
    /// and replaced when a new token is acquired (chaining), when
    /// ``registerProvider(_:)`` runs, or when the foreground transition handler
    /// detects that the wall-clock target has already passed.
    private var refreshTask: Task<Void, Never>?

    /// Absolute wall-clock target for the next proactive refresh, or `nil` when
    /// no refresh is scheduled. Stored as an absolute `Date` rather than a
    /// duration so the sleep loop can re-check against the *current* clock on
    /// every wakeup — `Task.sleep` drifts during backgrounding, so trusting the
    /// elapsed-sleep duration alone would fire late.
    private var refreshAtWallClock: Date?

    /// Long-lived Combine subscription that dispatches foreground transitions to
    /// ``handleForegroundTransition()``. Bound to the actor's lifetime (started in
    /// ``init`` and survives ``registerProvider(_:)``).
    private var lifecycleCancellable: AnyCancellable?

    /// Multicast hub for the proactive-refresh token stream. Each successful
    /// proactive refresh sends the new token here (see ``performScheduledRefresh()``);
    /// every active ``refreshes()`` subscriber receives it.
    ///
    /// A `PassthroughSubject` rather than a hand-rolled collection of
    /// `AsyncStream.Continuation`s: the subject natively fans a single
    /// `send(_:)` out to N subscribers and disposes each subscription via its
    /// returned cancellable, so there is no continuation bookkeeping for the
    /// actor to get wrong. ``refreshes()`` bridges it into a per-caller
    /// `AsyncStream` with the same `sink`-based pattern the lifecycle observer
    /// uses.
    ///
    /// Deliberately retained across both ``registerProvider(_:)`` and
    /// ``clearTokenState()``: a live form display keeps its subscription across
    /// provider swaps and profile resets, and the stream simply goes quiet
    /// until the next successful refresh produces a token to deliver.
    private let refreshSubject = PassthroughSubject<String, Never>()

    /// Lifecycle event source. Injected for testability; defaults to the
    /// SDK-wide `environment.appLifeCycle`.
    private let lifeCycle: AppLifeCycleEvents

    /// Wall-clock source. Injected for testability; defaults to the SDK-wide
    /// `environment.date` closure. Used by cached-token validity checks, the JWT
    /// validation on acquisition, and the proactive-refresh scheduling formula
    /// so a single time source drives every clock-sensitive decision the actor
    /// makes.
    private let currentDate: () -> Date

    /// Sleep primitive backing the proactive-refresh loop. Injected for
    /// testability so tests can drive the schedule deterministically rather than
    /// waiting on real wall-clock time; defaults to `Task.sleep(nanoseconds:)`.
    /// Cancellation is observed through the enclosing task's `Task.isCancelled`
    /// check in ``sleepUntilAndRefresh(target:)``, so the default deliberately
    /// swallows the `CancellationError` `Task.sleep` throws.
    private let sleeper: @Sendable (UInt64) async -> Void

    /// Production initializer. Wires the actor to the real SDK-wide clock
    /// (`environment.date`) and `Task.sleep`. This is the only initializer
    /// visible to sibling product modules, and is what ``shared`` uses.
    ///
    /// - Parameter lifeCycle: Source of foreground/background events. Defaults
    ///   to `environment.appLifeCycle`.
    package init(lifeCycle: AppLifeCycleEvents = environment.appLifeCycle) {
        self.lifeCycle = lifeCycle
        currentDate = { environment.date() }
        sleeper = { nanoseconds in try? await Task.sleep(nanoseconds: nanoseconds) }
        Task { await self.startLifecycleObserver() }
    }

    /// Test-only initializer that injects the time sources the production path
    /// hardcodes, so suites can drive token validity, refresh scheduling, and
    /// refresh firing in deterministic virtual time.
    ///
    /// Deliberately `internal` rather than `package`: it is reachable from the
    /// test target via `@testable import KlaviyoCore`, but invisible to sibling
    /// product modules' normal imports — the closest Swift gets to a
    /// "test-target-only" symbol. It is *not* wrapped in `#if DEBUG`, because the
    /// suite is also exercised in the release configuration
    /// (`make CONFIG=release test-library`), where a debug-only initializer
    /// would fail to compile. The required `currentDate` (no default) keeps this
    /// from overlapping with the no-argument production initializer above.
    ///
    /// - Parameters:
    ///   - lifeCycle: Source of foreground/background events.
    ///   - currentDate: Wall-clock source driving every clock-sensitive decision.
    ///   - sleep: Sleep primitive for the refresh loop, taking a duration in
    ///     nanoseconds. Defaults to `Task.sleep(nanoseconds:)`.
    init(
        lifeCycle: AppLifeCycleEvents = environment.appLifeCycle,
        currentDate: @escaping () -> Date,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.lifeCycle = lifeCycle
        self.currentDate = currentDate
        sleeper = sleep
        Task { await self.startLifecycleObserver() }
    }

    /// Registers a new provider, discards any cached token from a previous
    /// provider, cancels any in-flight fetch, and triggers an eager fetch to
    /// warm the cache.
    ///
    /// The eager fetch is fire-and-forget so registration call sites stay
    /// responsive — failures during the warm-up surface only as logs (the same
    /// logs ``currentToken(mode:)`` would emit). Calling this again later
    /// replaces the previous provider.
    package func registerProvider(_ newProvider: @escaping AuthTokenProvider) async {
        cancelInFlightWorkAndClearCache()
        provider = newProvider

        if #available(iOS 14.0, *) {
            Logger.auth.info("AuthTokenManager: provider registered")
        }
        Task {
            // fetch a token to warm the cache
            _ = try? await self.currentToken(mode: .background)
        }
    }

    /// Returns the current auth token, fetching one via the registered provider
    /// if the cache is empty or has gone stale.
    ///
    /// Concurrent callers share the in-flight fetch — exactly one provider
    /// invocation runs even under N simultaneous calls. Each caller's wait is
    /// bounded by ``FetchMode``; on timeout the *caller* throws
    /// ``AuthTokenError/timedOut`` while the underlying fetch task continues
    /// (and may still warm the cache for later callers).
    ///
    /// The SDK does not enforce an upper bound on the underlying fetch's
    /// runtime. If the host's provider closure hangs indefinitely without
    /// honoring cancellation, subsequent calls dedup with the stuck fetch and
    /// uniformly throw ``AuthTokenError/timedOut``; the slot only recovers when
    /// ``registerProvider(_:)`` runs again. Hosts must give their provider
    /// closure a finite upper-bound (e.g., `URLSession`'s default
    /// `timeoutIntervalForRequest` is sufficient).
    ///
    /// - Parameter mode: Latency budget for *this* call. Defaults to
    ///   ``FetchMode/interactive`` — the form-display path.
    /// - Throws: ``AuthTokenError/noProviderRegistered`` when no provider is
    ///   registered; ``AuthTokenError/timedOut`` when the caller's budget
    ///   elapses before the fetch completes; the provider's own error when the
    ///   provider throws; ``AuthTokenError/validationFailed(_:)`` when the
    ///   returned token fails ``JWTParser`` validation.
    package func currentToken(mode: FetchMode = .interactive) async throws -> String {
        if let cachedToken, isCachedTokenValid(cachedToken) {
            return cachedToken.rawToken
        }

        guard provider != nil else {
            throw AuthTokenError.noProviderRegistered
        }

        let task = inFlight?.task ?? startFetch()
        return try await race(fetch: task, timeoutSeconds: mode.rawValue)
    }

    /// Returns a stream of token strings produced by *proactive* refreshes.
    ///
    /// Each call returns an independent `AsyncStream` backed by its own
    /// subscription to ``refreshSubject``; multiple concurrent subscribers are
    /// supported. Only tokens from the proactive-refresh success path are
    /// delivered (see ``performScheduledRefresh()``) — interactive
    /// ``currentToken(mode:)`` fetches and the eager warm-up fetch do not emit
    /// here. The stream never finishes on its own and never errors; the
    /// consumer ends it by cancelling its iteration, which tears down the
    /// underlying Combine subscription via `onTermination`.
    ///
    /// The subscription is established synchronously inside the stream's build
    /// closure, so a refresh that fires immediately after this call is still
    /// delivered — there is no gap between subscribing and being ready to
    /// receive. Intended for `KlaviyoForms` to push refreshed tokens into an
    /// active WebView.
    ///
    /// Why a stream and not the ``refreshSubject`` itself: the subject is
    /// actor-isolated, and its `.send(_:)` write end must never cross the
    /// package boundary (a consumer could otherwise inject tokens to every
    /// subscriber). The SDK exposes Combine signals only as erased publishers
    /// or async streams, never as bare subjects. An `AsyncStream` keeps this
    /// API consistent with the manager's async/await surface and lets consumers
    /// iterate with `for await`.
    package func refreshes() -> AsyncStream<String> {
        AsyncStream { [refreshSubject] continuation in
            let cancellable = refreshSubject.sink { continuation.yield($0) }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Clears all token-acquisition state tied to the current user, called from
    /// `KlaviyoSDK().resetProfile()` (e.g. on logout). Discards the cached
    /// token, cancels the scheduled proactive refresh and its wall-clock
    /// target, and cancels any in-flight fetch.
    ///
    /// Deliberately *retains* three things:
    /// - ``provider`` — it is host integration code ("how to ask my auth system
    ///   for a token"), not user identity. The closure is expected to read the
    ///   current user fresh on each invocation, so the same provider serves the
    ///   next profile. The next ``currentToken(mode:)`` call drives the next
    ///   acquisition; this method does not eagerly re-invoke the provider.
    /// - ``lifecycleCancellable`` — the foreground observer is safe to leave
    ///   running across resets.
    /// - ``refreshSubject`` — active ``refreshes()`` subscriptions (e.g. a form
    ///   on screen during the reset) stay alive across the reset.
    package func clearTokenState() async {
        cancelInFlightWorkAndClearCache()
        if #available(iOS 14.0, *) {
            Logger.auth.info("AuthTokenManager: token state cleared")
        }
    }

    /// Cancels the in-flight fetch and scheduled refresh, then drops the cached
    /// token. Shared by ``registerProvider(_:)`` (which then installs a new
    /// provider and warms the cache) and ``clearTokenState()`` (which stops
    /// there). Does *not* touch ``provider``, ``lifecycleCancellable``, or
    /// ``refreshSubject`` — callers decide the fate of those.
    private func cancelInFlightWorkAndClearCache() {
        inFlight?.task.cancel()
        inFlight = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshAtWallClock = nil
        cachedToken = nil
    }

    /// Creates a new in-flight fetch task, stores it on the actor, and returns
    /// it. Must be called from actor-isolated context.
    private func startFetch() -> Task<String, Error> {
        let fetchID = UUID()
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.runFetch(fetchID: fetchID)
        }
        inFlight = (id: fetchID, task: task)
        return task
    }

    /// Body of the in-flight fetch task. Invokes the provider, validates the
    /// returned token, writes the cache on success, and clears its slot from
    /// the manager once it finishes — but only if it is still the *current*
    /// fetch (a swap via ``registerProvider(_:)`` may have installed a newer
    /// one in the meantime).
    private func runFetch(fetchID: UUID) async throws -> String {
        defer {
            if inFlight?.id == fetchID {
                inFlight = nil
            }
        }

        // Bail before reading `provider`: a task cancelled by `registerProvider(_:)`
        // before its body began executing would otherwise read the *new* provider
        // and invoke it, wasting an invocation and undermining dedup during rapid
        // provider swaps. The checkpoint after `provider()` below covers
        // cancellation that lands mid-fetch.
        try Task.checkCancellation()

        guard let provider else {
            throw AuthTokenError.noProviderRegistered
        }

        do {
            let rawToken = try await provider()
            // Explicit cancellation checkpoint: if `registerProvider(_:)` cancelled
            // us mid-fetch, the host's provider closure may not honor cancellation
            // and could return its (now-stale) token regardless. Throwing here
            // ensures we never write a stale token into the cache that has since
            // been bound to a newer provider.
            try Task.checkCancellation()

            switch JWTParser.parseAndValidate(rawToken, currentTime: currentDate()) {
            case let .success(validated):
                cachedToken = validated
                scheduleRefresh(for: validated)
                if #available(iOS 14.0, *) {
                    Logger.auth.info(
                        """
                        AuthTokenManager: token acquired \
                        (iat=\(validated.issuedAt, privacy: .private), \
                        exp=\(validated.expiresAt, privacy: .private))
                        """
                    )
                }
                return validated.rawToken
            case let .failure(failure):
                if #available(iOS 14.0, *) {
                    let reason = String(describing: failure)
                    Logger.auth.error(
                        "AuthTokenManager: validation failure on returned token: \(reason, privacy: .public)"
                    )
                }
                throw AuthTokenError.validationFailed(failure)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AuthTokenError {
            throw error
        } catch {
            if #available(iOS 14.0, *) {
                let reason = String(describing: error)
                Logger.auth.error(
                    "AuthTokenManager: provider error: \(reason, privacy: .public)"
                )
            }
            throw error
        }
    }

    /// Computes the wall-clock target for the proactive refresh of `token`.
    ///
    /// The ideal target is `iat + 0.9 * (exp - iat)` — fire when 90% of the
    /// token's lifetime has elapsed. That target is clamped to the window
    /// `[now + 5s, exp - JWTParser.defaultLeeway]`:
    ///
    /// - The upper bound matches the same skew window ``JWTParser`` uses for
    ///   the expiry check, so the refresh fires before the cache itself would
    ///   be considered stale.
    /// - The lower bound prevents tight refresh loops when a token is
    ///   acquired very close to its own expiration (e.g., a server returned a
    ///   short-lived token, or the system clock jumped forward).
    ///
    /// Pulled out as a static pure function so tests can verify the formula
    /// and clamps directly, without driving the full schedule-and-sleep
    /// lifecycle.
    static func refreshTarget(for token: ValidatedToken, currentDate: Date) -> Date {
        let total = token.expiresAt.timeIntervalSince(token.issuedAt)
        let ideal = token.issuedAt.addingTimeInterval(0.9 * total)
        let upperBound = token.expiresAt.addingTimeInterval(-JWTParser.defaultLeeway)
        let lowerBound = currentDate.addingTimeInterval(5)
        return max(lowerBound, min(ideal, upperBound))
    }

    /// Schedules a proactive refresh for `token`. Cancels any prior
    /// ``refreshTask`` so chained refreshes (success → schedule next) and
    /// provider swaps don't leak overlapping schedules.
    private func scheduleRefresh(for token: ValidatedToken) {
        let target = Self.refreshTarget(for: token, currentDate: currentDate())

        refreshTask?.cancel()
        refreshAtWallClock = target
        refreshTask = Task { [weak self] in
            await self?.sleepUntilAndRefresh(target: target)
        }

        if #available(iOS 14.0, *) {
            Logger.auth.info(
                "AuthTokenManager: refresh scheduled (target=\(target, privacy: .private))"
            )
        }
    }

    /// Sleeps until `target` wall-clock time, then fires
    /// ``performScheduledRefresh()``. The loop re-reads ``currentDate()`` on
    /// every wakeup rather than trusting that the ``sleeper`` slept the full
    /// requested duration: when the app is backgrounded, wall time advances but
    /// `Task.sleep` does not, so a single sleep would fire late by exactly the
    /// backgrounded duration. Re-checking the clock self-corrects — the next
    /// wakeup observes the post-jump time and exits.
    ///
    /// Not a polling loop. Each iteration sleeps the *full* remaining
    /// duration, so in the happy path the body runs at most ~2–3 times across
    /// the entire scheduled window (one long sleep, then a final short
    /// iteration that observes `remaining <= 0` and breaks).
    private func sleepUntilAndRefresh(target: Date) async {
        while !Task.isCancelled {
            let remaining = target.timeIntervalSince(currentDate())
            if remaining <= 0 { break }
            await sleeper(UInt64(remaining * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }
        refreshAtWallClock = nil
        await performScheduledRefresh()
    }

    /// Fires a proactive refresh by routing through the same dedup slot that
    /// user-driven ``currentToken(mode:)`` callers use. If a fetch is already
    /// in flight (e.g., a form-display caller raced ahead of the scheduled
    /// wakeup), this awaits that fetch instead of kicking off a second.
    ///
    /// On success: ``runFetch`` has already written the new token to the cache
    /// *and* scheduled the next refresh (via the wiring inside that method).
    /// On failure: leaves the cached token in place — the cache only goes
    /// stale at `exp - leeway`, so a foreground transition or user fetch
    /// before then will retry. Connectivity-driven retry is owned by MAGE-683.
    private func performScheduledRefresh() async {
        guard provider != nil else { return }
        let task = inFlight?.task ?? startFetch()
        do {
            let token = try await task.value
            if #available(iOS 14.0, *) {
                Logger.auth.info("AuthTokenManager: refresh succeeded")
            }
            // A profile reset (``clearTokenState()``) may have landed on the
            // actor while this fetch was suspended — `task.value` does not honor
            // the awaiter's cancellation, so we can resume holding a token that
            // belongs to the *outgoing* profile. Only broadcast a token that is
            // still the live cached value; otherwise drop it so stale-profile
            // tokens never reach live ``refreshes()`` subscribers.
            guard cachedToken?.rawToken == token else { return }
            refreshSubject.send(token)
        } catch {
            if #available(iOS 14.0, *) {
                let reason = String(describing: error)
                Logger.auth.warning(
                    "AuthTokenManager: refresh failed: \(reason, privacy: .public)"
                )
            }
        }
    }

    /// Starts the long-lived Combine subscription that drives
    /// ``handleForegroundTransition()`` on each `.foregrounded` event. Idempotent:
    /// no-op if the observer is already running, so retry-on-restart paths can
    /// call this safely.
    ///
    /// The `sink` closure is non-isolated, so each event hops back onto the actor
    /// via an unstructured `Task`. Foreground events are not bursty (a
    /// `.foregrounded` is always preceded by a `.backgrounded`), and the actor
    /// already serializes the state `handleForegroundTransition()` touches, so the
    /// lack of cross-event ordering between those tasks is immaterial.
    private func startLifecycleObserver() {
        guard lifecycleCancellable == nil else { return }
        lifecycleCancellable = lifeCycle.lifeCycleEvents()
            .sink { [weak self] event in
                guard case .foregrounded = event else { return }
                Task { [weak self] in await self?.handleForegroundTransition() }
            }
    }

    /// Reconciles cache and scheduled-refresh state with wall-clock time when
    /// the app returns to the foreground. `Task.sleep` does not advance during
    /// backgrounding, so any scheduled refresh whose target fell inside the
    /// background window will not have fired yet — and a sufficiently long
    /// background window can outlive the cached token entirely.
    ///
    /// Three cases, in this order:
    /// 1. Cached token expired during backgrounding — clear cache, cancel any
    ///    pending refresh, kick off an eager fetch so a subsequent caller
    ///    isn't the one paying the round-trip.
    /// 2. Scheduled refresh time has passed but the cache is still valid —
    ///    cancel the stuck refresh task and fire the refresh immediately.
    /// 3. Cache valid and refresh still in the future — no-op.
    private func handleForegroundTransition() async {
        if let cached = cachedToken, !isCachedTokenValid(cached) {
            cachedToken = nil
            refreshTask?.cancel()
            refreshTask = nil
            refreshAtWallClock = nil
            Task { [weak self] in
                _ = try? await self?.currentToken(mode: .background)
            }
            if #available(iOS 14.0, *) {
                Logger.auth.info(
                    "AuthTokenManager: foreground transition (case=expired-cached-token)"
                )
            }
            return
        }
        if let scheduled = refreshAtWallClock, currentDate() >= scheduled {
            refreshTask?.cancel()
            refreshTask = nil
            refreshAtWallClock = nil
            if #available(iOS 14.0, *) {
                Logger.auth.info(
                    "AuthTokenManager: foreground transition (case=missed-refresh)"
                )
            }
            await performScheduledRefresh()
            return
        }
        if #available(iOS 14.0, *) {
            Logger.auth.info(
                "AuthTokenManager: foreground transition (case=still-valid)"
            )
        }
    }

    /// Races the (shared) in-flight fetch against a `Task.sleep`-based timeout.
    /// Whichever finishes first determines the result for *this caller*. The
    /// underlying fetch task itself is not cancelled on timeout — other callers
    /// (and the cache-warming path) may still benefit if it eventually succeeds.
    ///
    /// Implemented via two detached tasks racing into a one-shot resolver
    /// rather than `withThrowingTaskGroup`. A task group implicitly awaits all
    /// children before its closure returns, and `Task.value` does not honor the
    /// awaiter's cancellation — so a group-based race would block the timeout
    /// path until the underlying provider returned anyway, defeating the
    /// purpose. The resolver lets the loser's resume become a no-op while the
    /// winning task drives the continuation.
    private nonisolated func race(
        fetch: Task<String, Error>,
        timeoutSeconds: TimeInterval
    ) async throws -> String {
        let timeoutNanos = UInt64(timeoutSeconds * 1_000_000_000)
        return try await withCheckedThrowingContinuation { continuation in
            let resolver = OnceResolver<String>(continuation)
            Task {
                do {
                    let value = try await fetch.value
                    await resolver.resolve(.success(value))
                } catch {
                    await resolver.resolve(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                let didTimeout = await resolver.resolve(.failure(AuthTokenError.timedOut))
                if didTimeout, #available(iOS 14.0, *) {
                    Logger.auth.error(
                        "AuthTokenManager: fetch timed out after \(timeoutSeconds, privacy: .public)s"
                    )
                }
            }
        }
    }

    /// `true` when the cached token's `exp` is still in the future after applying
    /// the same clock-skew leeway ``JWTParser`` uses on acquisition.
    private func isCachedTokenValid(_ token: ValidatedToken) -> Bool {
        let expiresAtSeconds = token.expiresAt.timeIntervalSince1970
        return currentDate().timeIntervalSince1970 < expiresAtSeconds - JWTParser.defaultLeeway
    }
}
