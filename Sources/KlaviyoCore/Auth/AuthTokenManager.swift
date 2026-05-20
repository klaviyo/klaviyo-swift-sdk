//
//  AuthTokenManager.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Foundation
import OSLog

/// Owns the host-supplied ``AuthTokenProvider`` and serves the current auth JWT to
/// internal SDK consumers (in-app forms today, future feature modules tomorrow).
///
/// This skeleton ships only the happy-path acquisition flow: register a provider,
/// fetch and validate a token, cache it, and hand the cached string to callers
/// until the next provider change. Concurrent-caller deduplication, timeout
/// enforcement, proactive refresh scheduling, the refresh notification stream, and
/// the `reset()` lifecycle hook will land in sibling sub-issues. Their stored
/// properties are declared here so adding those behaviors doesn't churn the
/// actor's shape.
///
/// The token cache is in-memory only — never persisted to disk or Keychain.
package actor AuthTokenManager {
    /// Shared instance used by `KlaviyoSDK` and other SDK modules. Tests should
    /// construct their own instances to keep test runs independent.
    package static let shared = AuthTokenManager()

    /// Most recently validated token, if any. Cleared whenever
    /// ``registerProvider(_:)`` runs.
    private var cachedToken: ValidatedToken?

    /// Host-supplied closure that returns a fresh JWT on each invocation.
    /// Starts `nil`; set by ``registerProvider(_:)``. There is no public API
    /// for clearing — that happens internally via ``reset()`` (deferred to a
    /// sibling sub-issue) when `KlaviyoSDK.resetProfile()` is called.
    private var provider: AuthTokenProvider?

    // MARK: - Deferred state

    // The following properties are declared as part of this actor's shape so
    // that sibling sub-issues can fill in their behaviors without churning the
    // signature. They are unused in this skeleton.

    /// Reserved for concurrent-caller deduplication. Sub-issue MAGE-624 will
    /// populate this from ``currentToken()`` so that multiple callers share a
    /// single provider invocation.
    private var inFlightFetch: Task<String, Error>?

    /// Reserved for proactive refresh scheduling. Sub-issue MAGE-625 will schedule
    /// refreshes at `iat + 0.9 * (exp - iat)` bounded by `[now + 5s, exp - 30s]`.
    private var refreshTask: Task<Void, Never>?

    /// Reserved for the refresh-notification stream. Sub-issue MAGE-626 will fan
    /// successful refresh tokens out to consumers via
    /// `refreshes() -> AsyncStream<String>`.
    private var refreshContinuations: [AsyncStream<String>.Continuation] = []

    init() {}

    /// Registers a new provider, discards any cached token from a previous
    /// provider, and triggers an eager fetch to warm the cache.
    ///
    /// The eager fetch is fire-and-forget so registration call sites stay
    /// responsive — failures during the warm-up surface only as logs (the same
    /// logs ``currentToken()`` would emit). Calling this again later replaces
    /// the previous provider; there is no public API for clearing a registered
    /// provider, since clearing is part of the profile-reset lifecycle handled
    /// in a sibling sub-issue.
    package func registerProvider(_ newProvider: @escaping AuthTokenProvider) async {
        cachedToken = nil
        provider = newProvider

        if #available(iOS 14.0, *) {
            Logger.auth.info("AuthTokenManager: provider registered")
        }
        Task {
            _ = try? await self.currentToken()
        }
    }

    /// Returns the current auth token, fetching one via the registered provider
    /// if the cache is empty or has gone stale.
    ///
    /// This is the happy-path skeleton: a single caller races directly against the
    /// provider, with no in-flight deduplication and no timeout enforcement. Those
    /// arrive in sub-issue MAGE-624; until then, two concurrent callers will both
    /// invoke the provider — the wrong behavior is "extra fetches", not data
    /// corruption.
    ///
    /// - Throws: ``AuthTokenError/noProviderRegistered`` when no provider is
    ///   registered; the provider's own error when the provider throws;
    ///   ``AuthTokenError/validationFailed(_:)`` when the returned token fails
    ///   ``JWTParser`` validation.
    package func currentToken() async throws -> String {
        if let cachedToken, isCachedTokenValid(cachedToken) {
            return cachedToken.rawToken
        }

        guard let provider else {
            throw AuthTokenError.noProviderRegistered
        }

        let rawToken = try await provider()

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
                Logger.auth.warning(
                    "AuthTokenManager: validation failure on returned token: \(reason, privacy: .public)"
                )
            }
            throw AuthTokenError.validationFailed(failure)
        }
    }

    /// `true` when the cached token's `exp` is still in the future after applying
    /// the same clock-skew leeway ``JWTParser`` uses on acquisition.
    private func isCachedTokenValid(_ token: ValidatedToken, currentTime: Date = Date()) -> Bool {
        let expiresAtSeconds = token.expiresAt.timeIntervalSince1970
        return currentTime.timeIntervalSince1970 < expiresAtSeconds - JWTParser.defaultLeeway
    }
}
