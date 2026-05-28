//
//  AuthTokenManager.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

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
        case bestEffort = 0.5

        /// 5s budget. Used by background acquisition paths (eager fetch at
        /// registration, scheduled refresh) where no user is actively waiting.
        case proactive = 5.0
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

    package init() {}

    /// Registers a new provider, discards any cached token from a previous
    /// provider, cancels any in-flight fetch, and triggers an eager fetch to
    /// warm the cache.
    ///
    /// The eager fetch is fire-and-forget so registration call sites stay
    /// responsive — failures during the warm-up surface only as logs (the same
    /// logs ``currentToken(mode:)`` would emit). Calling this again later
    /// replaces the previous provider.
    package func registerProvider(_ newProvider: @escaping AuthTokenProvider) async {
        inFlight?.task.cancel()
        inFlight = nil
        cachedToken = nil
        provider = newProvider

        if #available(iOS 14.0, *) {
            Logger.auth.info("AuthTokenManager: provider registered")
        }
        Task {
            // fetch a token to warm the cache
            _ = try? await self.currentToken(mode: .proactive)
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
    ///   ``FetchMode/bestEffort`` — the form-display path.
    /// - Throws: ``AuthTokenError/noProviderRegistered`` when no provider is
    ///   registered; ``AuthTokenError/timedOut`` when the caller's budget
    ///   elapses before the fetch completes; the provider's own error when the
    ///   provider throws; ``AuthTokenError/validationFailed(_:)`` when the
    ///   returned token fails ``JWTParser`` validation.
    package func currentToken(mode: FetchMode = .bestEffort) async throws -> String {
        if let cachedToken, isCachedTokenValid(cachedToken) {
            return cachedToken.rawToken
        }

        guard provider != nil else {
            throw AuthTokenError.noProviderRegistered
        }

        let task = inFlight?.task ?? startFetch()
        return try await race(fetch: task, timeoutSeconds: mode.rawValue)
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

            switch JWTParser.parseAndValidate(rawToken) {
            case let .success(validated):
                cachedToken = validated
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
        } catch is AuthTokenError {
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
    private func isCachedTokenValid(_ token: ValidatedToken, currentTime: Date = Date()) -> Bool {
        let expiresAtSeconds = token.expiresAt.timeIntervalSince1970
        return currentTime.timeIntervalSince1970 < expiresAtSeconds - JWTParser.defaultLeeway
    }
}

/// Serializes the first of two concurrent producers onto a `CheckedContinuation`
/// so that the loser's resume becomes a no-op. Used by ``AuthTokenManager`` to
/// race the in-flight fetch against a timeout without leaning on
/// `withThrowingTaskGroup` (which would block on the loser even after the
/// winner has resolved).
private actor OnceResolver<T> {
    private var resumed = false
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// - Returns: `true` if this call won the race and resumed the continuation;
    ///   `false` if the continuation was already resumed by an earlier call.
    @discardableResult
    func resolve(_ result: Result<T, Error>) -> Bool {
        guard !resumed else { return false }
        resumed = true
        switch result {
        case let .success(value): continuation.resume(returning: value)
        case let .failure(error): continuation.resume(throwing: error)
        }
        return true
    }
}
