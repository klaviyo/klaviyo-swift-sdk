//
//  AuthTokenProvider.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

/// Host-supplied closure that produces a Klaviyo auth JWT on demand.
///
/// The SDK invokes the provider whenever it needs a fresh token: at registration
/// time (eager fetch), when the cached token has expired, during proactive
/// refresh, and after the server rejected the current token.
///
/// The SDK caches the returned token and calls the provider again only when it
/// needs a new one (before expiry, or after the server rejected the current
/// token). Return a freshly issued token on every call; don't return one cached
/// from a previous call.
///
/// Returning a token from a long-lived async source (e.g. a network call
/// to the host's auth backend) is expected and supported — the SDK respects task
/// cancellation, so timeouts propagate cleanly for well-behaved implementations.
///
/// Returning a malformed or already-expired token causes the SDK to discard it and
/// log a validation failure; the SDK does not retry on its own.
public typealias AuthTokenProvider = @Sendable () async throws -> String
