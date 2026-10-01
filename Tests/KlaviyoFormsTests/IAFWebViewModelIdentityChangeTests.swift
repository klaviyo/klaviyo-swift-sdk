//
//  IAFWebViewModelIdentityChangeTests.swift
//  klaviyo-swift-sdk
//
//  Covers the auth token handed to a live page when the profile it holds is
//  replaced (e.g. by `resetProfile()` or `set(profile:)` with new identifiers).
//  Tokens reach the page through `IAFPresentationManager`'s token delivery, as in
//  production.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import Combine
import XCTest

private let outgoingProfile = ProfileData(email: "old@example.com", anonymousId: "anon-old")
private let incomingProfile = ProfileData(email: "new@example.com", anonymousId: "anon-new")

@MainActor
final class IAFWebViewModelIdentityChangeTests: XCTestCase {
    private var clock: TestClock!
    private var sleepGate: SleepGate!
    private var manager: AuthTokenManager!
    private var provider: ScriptedTokenProvider!
    private var presentationManager: IAFPresentationManager!
    private var viewModel: IAFWebViewModel!
    private var delegate: MockIAFWebViewDelegate!

    override func setUp() async throws {
        try await super.setUp()
        seedCoreStores()
        IdentityStore.shared.update(outgoingProfile)

        let clock = TestClock()
        let sleepGate = SleepGate()
        self.clock = clock
        self.sleepGate = sleepGate
        manager = AuthTokenManager(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() }),
            currentDate: { clock.now() },
            sleep: { await sleepGate.sleep($0) }
        )
        provider = ScriptedTokenProvider(currentDate: { clock.now() })
        presentationManager = IAFPresentationManager(viewController: nil)
    }

    override func tearDown() async throws {
        presentationManager.destroyWebView()
        await manager.unregisterProvider()
        presentationManager = nil
        viewModel = nil
        delegate = nil
        manager = nil
        provider = nil
        sleepGate = nil
        resetPresentationManagerStores()
        try await super.tearDown()
    }

    // MARK: - Identity replacements

    func testIdentityChangeDeliversTokenForNewProfileAfterProfileWrite() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)

        await changeIdentity(to: incomingProfile, writing: "anon-new")

        let incomingToken = try await awaitDelivery(ofInvocation: 2)
        assertOnlyTokenPushed(incomingToken, afterProfileWriteContaining: "anon-new")
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains(outgoingToken) })
    }

    func testOutgoingFetchCompletingAfterIdentityChangeIsNeitherPushedNorCached() async throws {
        _ = await provider.hold(invocation: 1)
        try await registerProvider()
        await provider.waitFor(invocations: 1)
        let manager = try XCTUnwrap(manager)
        let outgoingFetch = Task { try? await manager.currentToken(mode: .background) }
        await makeViewModel()

        await changeIdentity(to: incomingProfile, writing: "anon-new")
        await provider.waitForCancellation(invocation: 1)
        _ = await outgoingFetch.value

        let incomingToken = try await awaitDelivery(ofInvocation: 2)
        assertOnlyTokenPushed(incomingToken, afterProfileWriteContaining: "anon-new")
        let cached = try await manager.currentToken(mode: .background)
        XCTAssertEqual(cached, incomingToken)
        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 2)
    }

    func testClearLandingDuringIdentityFetchStillDeliversToken() async throws {
        _ = try await registerProviderAndWarmCache()
        _ = await provider.hold(invocation: 2)
        await makeViewModel()

        IdentityStore.shared.update(incomingProfile)
        await provider.waitFor(invocations: 2)
        // Stands in for the reducer's fire-and-forget clear arriving after Forms' own.
        await manager.clearTokenState()
        await provider.waitForCancellation(invocation: 2)
        await awaitProfileUpdate(writing: "anon-new")

        let retriedToken = try await awaitDelivery(ofInvocation: 3)
        assertOnlyTokenPushed(retriedToken, afterProfileWriteContaining: "anon-new")
    }

    func testRefreshInFlightAtIdentityChangeIsSupersededByTokenForNewProfile() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await sleepGate.waitUntilSleeping(atLeast: 1)
        _ = await provider.hold(invocation: 2)
        await makeViewModel(authToken: outgoingToken)

        // Past the warm token's refresh target (90% of its lifetime) while it is still valid.
        clock.advance(by: 3300)
        await sleepGate.release()
        await provider.waitFor(invocations: 2)
        await changeIdentity(to: incomingProfile, writing: "anon-new")
        await provider.waitForCancellation(invocation: 2)

        let refreshToken = try await minted(2)
        let incomingToken = try await awaitDelivery(ofInvocation: 3)
        assertOnlyTokenPushed(incomingToken, afterProfileWriteContaining: "anon-new")
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains(refreshToken) })
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains(outgoingToken) })
    }

    func testOnlyLatestIdentityTokenIsDeliveredAfterTwoQuickChanges() async throws {
        _ = try await registerProviderAndWarmCache()
        _ = await provider.hold(invocation: 2)
        await makeViewModel()
        let latestProfile = ProfileData(email: "latest@example.com", anonymousId: "anon-latest")

        IdentityStore.shared.update(incomingProfile)
        await provider.waitFor(invocations: 2)
        let firstChange = viewModel.profileUpdateTask
        await changeIdentity(to: latestProfile, writing: "anon-latest")
        await firstChange?.value

        let firstChangeToken = try await minted(2)
        let latestToken = try await awaitDelivery(ofInvocation: 3)
        assertOnlyTokenPushed(latestToken, afterProfileWriteContaining: "anon-latest")
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains(firstChangeToken) })
    }

    func testAddingEmailToAnonymousProfileFetchesFirstToken() async throws {
        let anonymousProfile = ProfileData(anonymousId: "anon-old")
        let identifiedProfile = ProfileData(email: "new@example.com", anonymousId: "anon-old")
        IdentityStore.shared.update(anonymousProfile)
        try await registerProvider()
        await makeViewModel(profileData: anonymousProfile)

        await changeIdentity(to: identifiedProfile, writing: "new@example.com")

        let identifiedToken = try await awaitDelivery(ofInvocation: 1)
        assertOnlyTokenPushed(identifiedToken, afterProfileWriteContaining: "new@example.com")
        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 1, "the provider must not be invoked while the profile is anonymous")
    }

    func testResetToAnonymousDropsTokenWithoutFetchingOrWritingOne() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)

        await changeIdentity(to: ProfileData(anonymousId: "anon-reset"), writing: "anon-reset")

        XCTAssertNil(viewModel.authToken)
        XCTAssertTrue(delegate.authTokenScripts.isEmpty)
        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 1)
    }

    func testCompatibleChangeRightAfterReplacementStillDeliversTokenForNewProfile() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)
        let compatibleProfile = ProfileData(
            email: "new@example.com",
            phoneNumber: "+15551234567",
            anonymousId: "anon-new"
        )

        IdentityStore.shared.update(incomingProfile)
        IdentityStore.shared.update(compatibleProfile)
        let incomingToken = try await awaitDelivery(ofInvocation: 2)

        XCTAssertEqual(viewModel.profileData, compatibleProfile)
        XCTAssertEqual(viewModel.authToken, incomingToken)
        assertOnlyTokenPushed(incomingToken, afterProfileWriteContaining: "anon-new")
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains(outgoingToken) })
    }

    func testPushFromOutgoingGenerationIsDeclinedAfterReplacement() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)
        let outgoingGeneration = manager.currentIdentityGeneration
        await changeIdentity(to: incomingProfile, writing: "anon-new")
        let incomingToken = try await awaitDelivery(ofInvocation: 2)

        let pushed = await viewModel.pushAuthToken(outgoingToken, generation: outgoingGeneration)

        XCTAssertFalse(pushed)
        XCTAssertEqual(viewModel.authToken, incomingToken)
        XCTAssertFalse(delegate.authTokenScripts.contains { $0.contains(outgoingToken) })
    }

    func testSameTokenAfterReplacementIsDeliveredAgain() async throws {
        let token = try makeTestJWT(subject: "same", validAt: clock.now())
        let counter = InvocationCounter()
        await manager.registerProvider {
            await counter.increment()
            return token
        }
        _ = try await manager.currentToken(mode: .background)
        await makeViewModel(authToken: token)

        await changeIdentity(to: incomingProfile, writing: "anon-new")
        await delegate.waitForScript(containing: token)

        let invocations = await counter.value
        XCTAssertEqual(invocations, 2)
        assertOnlyTokenPushed(token, afterProfileWriteContaining: "anon-new")
        XCTAssertEqual(viewModel.authToken, token)
    }

    // MARK: - Profile-before-token ordering

    func testTokenPublishedBeforeProfileWriteIsNeverWrittenAheadOfProfile() async throws {
        _ = try await registerProviderAndWarmCache()
        await makeViewModel()
        let profileWrite = delegate.holdScript(containing: "anon-new")

        IdentityStore.shared.update(incomingProfile)
        await profileWrite.reached.wait()
        // Another consumer's fetch publishes a token while the profile write is in flight.
        let otherFetchToken = try await manager.currentToken(mode: .background)
        await profileWrite.release.open()

        let delivered = try await awaitDelivery(ofInvocation: 2)
        XCTAssertEqual(delivered, otherFetchToken)
        assertOnlyTokenPushed(otherFetchToken, afterProfileWriteContaining: "anon-new")
    }

    func testPushIsDeclinedWhileIdentityStoreIsAheadOfPage() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)
        let staleToken = try makeTestJWT(subject: "stale", validAt: clock.now())

        IdentityStore.shared.update(incomingProfile)
        let wasWritten = await viewModel.pushAuthToken(staleToken)

        XCTAssertFalse(wasWritten)
        XCTAssertEqual(viewModel.authToken, outgoingToken)
        await awaitProfileUpdate(writing: "anon-new")
        let incomingToken = try await awaitDelivery(ofInvocation: 2)
        assertOnlyTokenPushed(incomingToken, afterProfileWriteContaining: "anon-new")
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains(staleToken) })
    }

    // MARK: - Updates that keep the token

    func testRepublishingSameProfileDoesNotRefetchToken() async throws {
        _ = try await registerProviderAndWarmCache()
        await makeViewModel()

        IdentityStore.shared.update(outgoingProfile)
        // A later identity change gives the test something to wait for.
        await changeIdentity(to: incomingProfile, writing: "anon-new")
        _ = try await awaitDelivery(ofInvocation: 2)

        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 2)
        XCTAssertEqual(delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-profile") }.count, 1)
    }

    func testFirstProfileWrittenToPageDoesNotRefetchToken() async throws {
        _ = try await registerProviderAndWarmCache()
        // The subscription delivers the current profile to a page that has none yet.
        await makeViewModel(profileData: nil)
        await awaitProfileUpdate(writing: "anon-old")

        let invocationsAfterFirstWrite = await provider.invocationCount
        XCTAssertEqual(invocationsAfterFirstWrite, 1)
        XCTAssertTrue(delegate.authTokenScripts.isEmpty)

        await changeIdentity(to: incomingProfile, writing: "anon-new")
        _ = try await awaitDelivery(ofInvocation: 2)

        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 2)
        XCTAssertEqual(delegate.authTokenScripts.count, 1)
    }

    func testNewAnonymousIdForSameEmailKeepsToken() async throws {
        try await assertCompatibleChangeKeepsToken(
            to: ProfileData(email: "old@example.com", anonymousId: "anon-other"),
            writing: "anon-other"
        )
    }

    func testAddingPhoneNumberToSameEmailKeepsToken() async throws {
        try await assertCompatibleChangeKeepsToken(
            to: ProfileData(email: "old@example.com", phoneNumber: "+15555550100", anonymousId: "anon-old"),
            writing: "+15555550100"
        )
    }

    func testSameTokenAfterCompatibleChangeIsNotPushedAgain() async throws {
        let token = try makeTestJWT(subject: "same", validAt: clock.now())
        let sentinel = try makeTestJWT(subject: "sentinel", validAt: clock.now())
        let counter = InvocationCounter()
        await manager.registerProvider {
            await counter.increment() <= 2 ? token : sentinel
        }
        _ = try await manager.currentToken(mode: .background)
        await makeViewModel(authToken: token)

        await changeIdentity(
            to: ProfileData(email: "old@example.com", anonymousId: "anon-other"),
            writing: "anon-other"
        )
        await refetch()
        await refetch()
        await delegate.waitForScript(containing: sentinel)

        let invocations = await counter.value
        XCTAssertEqual(invocations, 3)
        XCTAssertEqual(delegate.authTokenScripts.count, 1, "the unchanged token must not be pushed again")
        XCTAssertTrue(delegate.authTokenScripts.first?.contains(sentinel) ?? false)
    }

    func testIdentityChangeWithoutProviderWritesProfileOnly() async {
        await makeViewModel()

        await changeIdentity(to: incomingProfile, writing: "anon-new")

        XCTAssertTrue(delegate.authTokenScripts.isEmpty)
    }

    // MARK: - Load scripts

    func testLoadScriptsCarryLatestProfileAndToken() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)

        await changeIdentity(to: incomingProfile, writing: "anon-new")
        let incomingToken = try await awaitDelivery(ofInvocation: 2)

        let profileScripts = loadScriptSources(containing: "data-klaviyo-profile")
        let tokenScripts = loadScriptSources(containing: "data-klaviyo-jwt")
        XCTAssertEqual(profileScripts.count, 1)
        XCTAssertTrue(profileScripts.first?.contains("anon-new") ?? false)
        XCTAssertEqual(tokenScripts.count, 1)
        XCTAssertTrue(tokenScripts.first?.contains(incomingToken) ?? false)
        XCTAssertEqual(viewModel.authToken, incomingToken)
    }

    func testLoadScriptsCarryLatestDeliveredToken() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)

        await refetch()
        let refreshedToken = try await awaitDelivery(ofInvocation: 2)

        let tokenScripts = loadScriptSources(containing: "data-klaviyo-jwt")
        XCTAssertEqual(tokenScripts.count, 1)
        XCTAssertTrue(tokenScripts.first?.contains(refreshedToken) ?? false)
        XCTAssertFalse(tokenScripts.first?.contains(outgoingToken) ?? true)
        XCTAssertEqual(viewModel.authToken, refreshedToken)
    }

    func testIdentityChangeDropsOutgoingTokenFromLoadScriptsBeforeFetchCompletes() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        let identityFetch = await provider.hold(invocation: 2)
        await makeViewModel(authToken: outgoingToken)
        XCTAssertEqual(loadScriptSources(containing: outgoingToken).count, 1)

        IdentityStore.shared.update(incomingProfile)
        await provider.waitFor(invocations: 2)

        XCTAssertNil(viewModel.authToken)
        XCTAssertTrue(loadScriptSources(containing: "data-klaviyo-jwt").isEmpty)
        let profileScripts = loadScriptSources(containing: "data-klaviyo-profile")
        XCTAssertEqual(profileScripts.count, 1)
        XCTAssertTrue(profileScripts.first?.contains("anon-new") ?? false)

        await identityFetch.open()
        _ = try await awaitDelivery(ofInvocation: 2)
    }

    func testFailedIdentityFetchLeavesNoTokenInLoadScripts() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await provider.fail(invocation: 2)
        await makeViewModel(authToken: outgoingToken)

        await changeIdentity(to: incomingProfile, writing: "anon-new")

        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 2)
        XCTAssertNil(viewModel.authToken)
        XCTAssertTrue(loadScriptSources(containing: "data-klaviyo-jwt").isEmpty)
        XCTAssertTrue(delegate.authTokenScripts.isEmpty)
    }

    func testFailedProfileWriteClearsOutgoingTokenWithoutFetchingForNewProfile() async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)
        let profileWrite = delegate.holdScript(containing: "data-klaviyo-profile")
        delegate.failScript(containing: "data-klaviyo-profile")

        IdentityStore.shared.update(incomingProfile)
        await profileWrite.reached.wait()
        let replacement = viewModel.profileUpdateTask
        await profileWrite.release.open()
        await replacement?.value

        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 1, "no token may be fetched for a profile the page never received")
        let outgoingStillCached = await manager.isCurrentToken(outgoingToken)
        XCTAssertFalse(outgoingStillCached, "the outgoing token must not outlive the identity change")
        XCTAssertNil(viewModel.authToken)
        XCTAssertTrue(delegate.authTokenScripts.isEmpty)
    }

    func testFailedTokenWriteDoesNotSuppressTheSameTokenLater() async throws {
        let token = try makeTestJWT(subject: "same", validAt: clock.now())
        await manager.registerProvider { token }
        _ = try await manager.currentToken(mode: .background)
        await makeViewModel()
        let failedWrite = delegate.holdScript(containing: "data-klaviyo-jwt")
        delegate.failScript(containing: "data-klaviyo-jwt")

        await refetch()
        await failedWrite.reached.wait()
        await failedWrite.release.open()
        // The failed write must not count as delivered, so the same token is written next time.
        await refetch()

        await delegate.waitForScript(containing: token)
        XCTAssertEqual(delegate.authTokenScripts.count, 1)
    }
}

// MARK: - Helpers

extension IAFWebViewModelIdentityChangeTests {
    /// Builds a page holding `profileData` and `authToken` and starts token delivery to it
    /// through ``presentationManager``, as a completed handshake does.
    private func makeViewModel(profileData: ProfileData? = outgoingProfile, authToken: String? = nil) async {
        let updates = await manager.refreshes()
        let viewModel = IAFWebViewModel(
            url: URL(string: "https://example.com")!,
            apiKey: "abc123",
            profileData: profileData,
            authToken: authToken,
            authTokenManager: manager
        )
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        self.viewModel = viewModel
        self.delegate = delegate
        presentationManager.prepareTokenDelivery(
            for: viewModel,
            initialToken: authToken,
            initialProfile: profileData,
            updates: updates,
            from: manager
        )
        presentationManager.startTokenDelivery()
    }

    private func registerProvider() async throws {
        let provider = try XCTUnwrap(provider)
        await manager.registerProvider { try await provider.provide() }
    }

    /// Registers ``provider`` and returns the token its first invocation cached.
    private func registerProviderAndWarmCache() async throws -> String {
        try await registerProvider()
        let token = try await manager.currentToken(mode: .background)
        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 1)
        return token
    }

    /// Drops the cached token and fetches a new one, which the fetch publishes to delivery.
    /// Returns once the new token is published, with no wall-clock bound on the wait.
    private func refetch() async {
        let updates = await manager.refreshes()
        await manager.clearTokenState()
        Task { [manager] in _ = try? await manager?.currentToken(mode: .background) }
        for await _ in updates {
            return
        }
    }

    private func minted(
        _ invocation: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> String {
        let token = await provider.token(invocation)
        return try XCTUnwrap(token, "provider invocation \(invocation) never ran", file: file, line: line)
    }

    /// Waits for the token minted by provider invocation `invocation` to be written to the
    /// page, and returns it.
    private func awaitDelivery(
        ofInvocation invocation: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> String {
        await provider.waitFor(invocations: invocation)
        let token = try await minted(invocation, file: file, line: line)
        await delegate.waitForScript(containing: token, file: file, line: line)
        return token
    }

    /// Publishes `profile`, then waits for the view model to write it to the page and
    /// finish any token-state clear and fetch the change triggered.
    private func changeIdentity(
        to profile: ProfileData,
        writing marker: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        IdentityStore.shared.update(profile)
        await awaitProfileUpdate(writing: marker, file: file, line: line)
    }

    /// Waits for a page write containing `marker`, then for the profile update task that
    /// made it to finish.
    private func awaitProfileUpdate(
        writing marker: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await delegate.waitForScript(containing: marker, file: file, line: line)
        await viewModel.profileUpdateTask?.value
    }

    /// Changes the page's profile to `profile`, which must be compatible with
    /// `outgoingProfile`, and asserts the profile is written while the outgoing token stays
    /// cached, injected and unrefetched.
    private func assertCompatibleChangeKeepsToken(
        to profile: ProfileData,
        writing marker: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let outgoingToken = try await registerProviderAndWarmCache()
        await makeViewModel(authToken: outgoingToken)

        await changeIdentity(to: profile, writing: marker, file: file, line: line)

        XCTAssertEqual(viewModel.profileData, profile, file: file, line: line)
        XCTAssertTrue(delegate.authTokenScripts.isEmpty, file: file, line: line)
        XCTAssertEqual(viewModel.authToken, outgoingToken, file: file, line: line)
        XCTAssertEqual(loadScriptSources(containing: outgoingToken).count, 1, file: file, line: line)
        let cached = try await manager.currentToken(mode: .background)
        XCTAssertEqual(cached, outgoingToken, file: file, line: line)
        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 1, "a compatible change must not refetch", file: file, line: line)
    }

    private func loadScriptSources(containing text: String) -> [String] {
        (viewModel.loadScripts ?? []).map(\.source).filter { $0.contains(text) }
    }

    /// Asserts `token` is the only auth token pushed, and that it followed a profile write
    /// containing `profileMarker`.
    private func assertOnlyTokenPushed(
        _ token: String,
        afterProfileWriteContaining profileMarker: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tokenScripts = delegate.authTokenScripts
        XCTAssertEqual(tokenScripts.count, 1, "expected exactly one token push", file: file, line: line)
        XCTAssertTrue(tokenScripts.first?.contains(token) ?? false, file: file, line: line)

        let scripts = delegate.evaluatedScripts
        let profileIndex = scripts.firstIndex {
            $0.contains("data-klaviyo-profile") && $0.contains(profileMarker)
        }
        guard let profileIndex,
              let tokenIndex = scripts.firstIndex(where: { $0.contains(token) }) else {
            XCTFail("expected both a profile write and a token push", file: file, line: line)
            return
        }
        XCTAssertLessThan(
            profileIndex,
            tokenIndex,
            "token must be pushed after the profile write",
            file: file,
            line: line
        )
    }
}
