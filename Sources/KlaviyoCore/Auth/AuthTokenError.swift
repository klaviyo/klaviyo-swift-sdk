//
//  AuthTokenError.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

import Foundation

/// Errors thrown by ``AuthTokenManager`` when an auth-token request cannot be
/// satisfied.
///
/// The SDK does not surface these to host code via callback — failures are
/// observable only via OSLog and form-display behavior. The cases exist so SDK
/// modules that consume ``AuthTokenManager`` (e.g. `KlaviyoForms`) can
/// distinguish between "no provider has been registered yet" and "the provider
/// returned an invalid token" when shaping their fallback behavior.
package enum AuthTokenError: Error, Equatable {
    /// ``currentToken()`` was called before any ``AuthTokenProvider`` was
    /// registered. Callers should treat this as "auth is not enabled" rather
    /// than "auth failed".
    case noProviderRegistered

    /// The profile has no identifier (email, phone number, or external ID), so the
    /// provider was not invoked. Callers should proceed without a token, as for
    /// ``noProviderRegistered``.
    case noProfileIdentifier

    /// The provider returned a token that did not pass ``JWTParser`` validation.
    /// The associated value carries the specific reason (malformed, expired,
    /// missing claim, …).
    case validationFailed(JWTValidationFailure)

    /// The provider did not produce a token within the caller's timeout budget.
    /// The underlying fetch task may still be running and will write to the cache
    /// if it eventually succeeds; the timeout only bounds the *caller's* wait.
    case timedOut

    /// The configured company changed while the caller was waiting on the fetch,
    /// so the fetched token belongs to the previous company and was discarded.
    case companyChanged
}
