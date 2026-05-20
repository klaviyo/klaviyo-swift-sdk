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
/// The token cache is in-memory only — never persisted to disk or Keychain.
package actor AuthTokenManager {
    /// Shared instance used by `KlaviyoSDK` and other SDK modules. Tests should
    /// construct their own instances to keep test runs independent.
    package static let shared = AuthTokenManager()

    /// Most recently validated token, if any. Cleared whenever
    /// ``registerProvider(_:)`` runs.
    private var cachedToken: ValidatedToken?

    /// Host-supplied closure that returns a fresh JWT on each invocation.
    /// Starts `nil`; set by ``registerProvider(_:)``.
    private var provider: AuthTokenProvider?

    init() {}

    /// Registers a new provider, discards any cached token from a previous
    /// provider, and triggers an eager fetch to warm the cache.
    ///
    /// The eager fetch is fire-and-forget so registration call sites stay
    /// responsive — failures during the warm-up surface only as logs (the same
    /// logs ``currentToken()`` would emit). Calling this again later replaces
    /// the previous provider.
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

        // TODO: [MAGE-624] cancel any in-flight fetch when `registerProvider(_:)`
        // runs — the resumed continuation below can otherwise overwrite the cache
        // with a token from a since-replaced provider.
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
