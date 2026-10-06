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

/// An `AuthTokenManager` like ``makeUnboundedAuthTokenManager()``, except that every caller's
/// fetch budget elapses once `fetchBudget` opens.
func makeAuthTokenManager(fetchBudget: Latch) -> AuthTokenManager {
    AuthTokenManager(
        currentDate: { environment.date() },
        fetchTimeoutSleep: { _ in await fetchBudget.wait() }
    )
}

/// Makes `manager` fetch and cache a valid token tagged with `subject`, and returns it with the
/// identity generation it was cached for. The current profile must have an identifier.
func cacheTestToken(
    subject: String,
    in manager: AuthTokenManager
) async throws -> AuthTokenManager.TokenRefresh {
    let token = try makeTestJWT(subject: subject, validAt: environment.date())
    await manager.registerProvider { token }
    return try await manager.currentTokenRefresh(mode: .background)
}

/// Stand-in for the manager's fetch-timeout sleep that never wakes, so a test's calls are not
/// bound by a real-time budget.
let neverTimesOut: @Sendable (UInt64) async -> Void = { _ in await Latch().wait() }

extension MockIAFWebViewDelegate {
    /// Upper bound for ``awaitScript(containing:file:line:)``, which only exists to fail a test
    /// whose script never arrives.
    static let scriptSafeguard: TimeInterval = 60

    /// Suspends until a script containing `text` has been evaluated, resuming as soon as it is.
    func awaitScript(
        containing text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitForScript(containing: text, timeout: Self.scriptSafeguard, file: file, line: line)
    }
}
