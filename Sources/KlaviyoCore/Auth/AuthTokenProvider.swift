//
//  AuthTokenProvider.swift
//  KlaviyoCore
//
//  Created by Andrew Balmer on 2026-05-14.
//

/// Host-supplied closure that produces a Klaviyo auth JWT on demand.
///
/// The SDK invokes the provider whenever it needs a fresh token: at registration
/// time (eager fetch), when the cached token has expired, and during proactive
/// refresh. Returning a token from a long-lived async source (e.g. a network call
/// to the host's auth backend) is expected and supported — the SDK respects task
/// cancellation, so timeouts propagate cleanly for well-behaved implementations.
///
/// Returning a malformed or already-expired token causes the SDK to discard it and
/// log a validation failure; the SDK does not retry on its own.
public typealias AuthTokenProvider = @Sendable () async throws -> String
