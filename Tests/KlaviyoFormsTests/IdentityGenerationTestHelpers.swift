//
//  IdentityGenerationTestHelpers.swift
//  klaviyo-swift-sdk
//
//  Shared fixtures for identity-generation auth-token tests.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import Foundation

/// An `AuthTokenManager` independent of `.shared` on the test environment's clock, whose
/// callers are never bound by a real-time fetch budget.
func makeUnboundedAuthTokenManager() -> AuthTokenManager {
    AuthTokenManager(
        currentDate: { environment.date() },
        fetchTimeoutSleep: neverTimesOut
    )
}

/// Stand-in for the manager's fetch-timeout sleep that never wakes, so a test's calls are not
/// bound by a real-time budget.
let neverTimesOut: @Sendable (UInt64) async -> Void = { _ in await Latch().wait() }
