//
//  AuthTokenPublicApiTests.swift
//  KlaviyoSwiftTests
//
//  End-to-end coverage of the auth-token flow driven ENTIRELY through the public
//  `KlaviyoSDK` facade: `registerAuthTokenProvider(_:)`, `set(profile:)`,
//  `set(email:)` and `resetProfile()`. Unlike `AuthTokenIdentityBehaviorTests`
//  (which drives `KlaviyoCommands` against an injected manager), the provider here
//  is registered on `AuthTokenManager.shared` exactly as host code would, and the
//  manager's cache state is asserted at every step.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

@MainActor
final class AuthTokenPublicApiTests: KlaviyoBaseTestCase {
    private var provider: RecordingAuthProvider!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        LifecycleState.shared.reset()
        _ = installSpyRequestQueue()
        provider = RecordingAuthProvider()
        // No provider may leak in from an earlier suite.
        await AuthTokenManager.shared.unregisterProvider()
        // Host usage initializes the SDK before setting profiles — without it the parity
        // gate drops profile writes pre-init and the flow under test never starts. The
        // public `initialize(with:)` returns before the async init tail runs; completing
        // initialization here through the test seam keeps the lifecycle deterministic.
        KlaviyoSDK().initialize(with: TEST_API_KEY)
        await KlaviyoCommands.completeInitialization(apiKey: TEST_API_KEY)
    }

    @MainActor
    override func tearDown() async throws {
        await AuthTokenManager.shared.unregisterProvider()
        provider = nil
        try await super.tearDown()
    }

    /// register → set profile → switch profile → reset, all through the public API:
    ///
    /// 1. Registering against an anonymous profile gates the provider (no call, no token).
    /// 2. `set(profile:)` identifies the profile and unblocks exactly one fetch; the token
    ///    it returns is the manager's current token.
    /// 3. Switching to a different identified profile retires the first token; the next
    ///    demand fetches exactly once and serves a distinct, current token.
    /// 4. `resetProfile()` retires the second token and re-gates the provider while the
    ///    profile is unidentified.
    func testPublicApiIdentityLifecycleDrivesProviderCallsAndCacheState() async throws {
        let klaviyoSDK = KlaviyoSDK()

        // 1. Register while anonymous: no eager fetch, no token to serve.
        klaviyoSDK.registerAuthTokenProvider { try await self.provider.provide() }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            provider.invocationCount, 0,
            "provider must not be called while the profile has no identifier"
        )
        await assertSharedManagerHasNoTokenWhileUnidentified()

        // 2. Identify through the public API: one fetch; served token is current.
        klaviyoSDK.set(profile: Profile(email: "one@example.com"))
        try await waitForConditionOrFail("the public set(profile:) must reach IdentityStore") {
            IdentityStore.shared.current.email == "one@example.com"
        }
        let firstToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        try await waitForConditionOrFail("identification must trigger exactly one fetch") {
            self.provider.invocationCount == 1
        }
        let firstIsCurrent = await AuthTokenManager.shared.isCurrentToken(firstToken)
        XCTAssertTrue(firstIsCurrent, "the token fetched on identification must be current")

        // 3. Switch identified profiles: the outgoing token retires; one fresh fetch.
        klaviyoSDK.set(profile: Profile(email: "two@example.com"))
        try await waitForConditionOrFail("the public profile switch must reach IdentityStore") {
            IdentityStore.shared.current.email == "two@example.com"
        }
        let firstStillCurrent = await AuthTokenManager.shared.isCurrentToken(firstToken)
        XCTAssertFalse(
            firstStillCurrent,
            "a replacing profile switch must retire the outgoing profile's token"
        )
        let secondToken = try await AuthTokenManager.shared.currentToken(mode: .background)
        XCTAssertNotEqual(secondToken, firstToken)
        try await waitForConditionOrFail("the profile switch must trigger exactly one new fetch") {
            self.provider.invocationCount == 2
        }
        let secondIsCurrent = await AuthTokenManager.shared.isCurrentToken(secondToken)
        XCTAssertTrue(secondIsCurrent, "the switched-in profile's token must be current")

        // 4. Reset through the public API: token retired, provider gated while anonymous.
        klaviyoSDK.resetProfile()
        try await waitForConditionOrFail("the public resetProfile() must reach IdentityStore") {
            IdentityStore.shared.current.email == nil
        }
        let secondStillCurrent = await AuthTokenManager.shared.isCurrentToken(secondToken)
        XCTAssertFalse(
            secondStillCurrent,
            "resetProfile() must retire the cached token"
        )
        await assertSharedManagerHasNoTokenWhileUnidentified()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            provider.invocationCount, 2,
            "provider must not be called again while the reset profile is unidentified"
        )
    }

    /// Asserts the shared manager refuses a token for an unidentified profile (and so,
    /// by contract, never invokes the provider for one).
    private func assertSharedManagerHasNoTokenWhileUnidentified(
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let token = try await AuthTokenManager.shared.currentToken(mode: .background)
            XCTFail("served a token for an unidentified profile: \(token)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AuthTokenError, .noProfileIdentifier, file: file, line: line)
        }
    }
}
