//
//  IAFPresentationManagerAuthTests.swift
//  klaviyo-swift-sdk
//
//  Auth token delivery to the live WebView: subscription ordering, handshake gating,
//  de-duplication, teardown and `refreshJwt` replacement.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import XCTest

@MainActor
final class IAFPresentationManagerAuthTests: XCTestCase {
    private var fileUrl: URL!
    private let profileA = ProfileData(email: "a@example.com", anonymousId: "anon-1")
    private let profileB = ProfileData(email: "b@example.com", anonymousId: "anon-1")

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        resetPresentationManagerStores()
        seedCoreStores()
        fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
    }

    override func tearDown() async throws {
        resetPresentationManagerStores()
        try await super.tearDown()
    }

    private func makeToken(_ subject: String) throws -> String {
        try makeTestJWT(subject: subject, validAt: environment.date())
    }

    private func makeViewModel(
        authToken: String?,
        authTokenManager: AuthTokenManager
    ) -> (IAFWebViewModel, MockIAFWebViewDelegate) {
        let viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: "abc123",
            profileData: nil,
            authToken: authToken,
            authTokenManager: authTokenManager
        )
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        return (viewModel, delegate)
    }

    private func jwtScripts(_ delegate: MockIAFWebViewDelegate) -> [String] {
        delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }
    }

    /// Returns the token `authTokenManager` serves, failing the test when the fetch fails or
    /// does not finish within ``hangSafeguard``.
    @discardableResult
    private func fetchToken(
        from authTokenManager: AuthTokenManager,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AuthTokenManager.TokenRefresh {
        try await awaitBounded("token fetch", file: file, line: line) {
            try await authTokenManager.currentTokenRefresh(mode: .background)
        }
    }

    /// Suspends until `counter` reaches `threshold`, failing the test when it does not within
    /// ``hangSafeguard``.
    private func waitForProviderCalls(
        _ counter: InvocationCounter,
        atLeast threshold: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await awaitBounded("provider call \(threshold)", file: file, line: line) {
            await counter.waitFor(atLeast: threshold)
        }
    }

    func testProfileChangedDuringTokenWaitIsUsedForInitialDocument() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("token")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let counter = InvocationCounter()
        let profileB = profileB
        await authTokenManager.registerProvider {
            if await counter.increment() == 2 {
                await MainActor.run { IdentityStore.shared.update(profileB) }
            }
            return token
        }
        try await waitForProviderCalls(counter, atLeast: 1)
        try await fetchToken(from: authTokenManager)
        await authTokenManager.clearTokenState()
        let manager = IAFPresentationManager(viewController: nil)
        manager.indexHtmlFileUrl = fileUrl
        manager.makeViewController = { InertWebViewController(hosting: $0) }

        try await awaitBounded("webview build") {
            try await manager.createFormWebViewAndListen(apiKey: "abc123", authTokenManager: authTokenManager)
        }

        let viewModel = try XCTUnwrap(manager.viewModel)
        XCTAssertEqual(viewModel.profileData, profileB)
        XCTAssertEqual(viewModel.authToken, token)
        let invocations = await counter.value
        XCTAssertEqual(invocations, 3, "the build's fetch must change the profile, then refetch for it")
        manager.destroyWebView()
    }

    func testCreatedViewModelUsesInjectedAuthTokenManager() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("token")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment()
            return token
        }
        try await fetchToken(from: authTokenManager)
        let manager = IAFPresentationManager(viewController: nil)
        manager.indexHtmlFileUrl = fileUrl
        manager.makeViewController = { InertWebViewController(hosting: $0) }

        try await manager.createFormWebViewAndListen(apiKey: "abc123", authTokenManager: authTokenManager)
        let viewModel = try XCTUnwrap(manager.viewModel)
        viewModel.receiveRefreshJwt()
        try await waitForProviderCalls(counter, atLeast: 2)

        let invocations = await counter.value
        XCTAssertEqual(invocations, 2, "refreshJwt must reach the manager the page was built with")
        manager.destroyWebView()
    }

    func testTokenArrivingBeforeHandshakeIsHeldThenDelivered() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("late")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let updates = await authTokenManager.refreshes()
        await authTokenManager.registerProvider { token }
        try await fetchToken(from: authTokenManager)
        let (viewModel, delegate) = makeViewModel(authToken: nil, authTokenManager: authTokenManager)
        let manager = IAFPresentationManager(viewController: nil)

        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: nil,
            initialProfile: IdentityStore.shared.current,
            updates: updates,
            from: authTokenManager
        )
        await Task.yield()
        XCTAssertTrue(jwtScripts(delegate).isEmpty)

        manager.startTokenDelivery()

        await assertEventually { !self.jwtScripts(delegate).isEmpty }
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(token))
        manager.destroyWebView()
    }

    func testLateTokenReachesLiveWebViewOnce() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("late")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let release = Latch()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment()
            await release.wait()
            return token
        }
        try await waitForProviderCalls(counter, atLeast: 1)
        let (viewModel, delegate) = makeViewModel(authToken: nil, authTokenManager: authTokenManager)
        let manager = IAFPresentationManager(viewController: nil)
        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: nil,
            initialProfile: IdentityStore.shared.current,
            updates: updates,
            from: authTokenManager
        )
        manager.startTokenDelivery()

        await release.open()

        await assertEventually { !self.jwtScripts(delegate).isEmpty }
        try await fetchToken(from: authTokenManager)
        await Task.yield()
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(token))
        manager.destroyWebView()
    }

    func testTokenAlreadyOnPageIsNotPushedAgainButNewTokenIs() async throws {
        IdentityStore.shared.update(profileA)
        let initial = try makeToken("initial")
        let next = try makeToken("next")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment() == 1 ? initial : next
        }
        try await fetchToken(from: authTokenManager)
        let (viewModel, delegate) = makeViewModel(authToken: initial, authTokenManager: authTokenManager)
        let manager = IAFPresentationManager(viewController: nil)
        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: initial,
            initialProfile: IdentityStore.shared.current,
            updates: updates,
            from: authTokenManager
        )
        manager.startTokenDelivery()

        await authTokenManager.clearTokenState()
        try await fetchToken(from: authTokenManager)

        await assertEventually { !self.jwtScripts(delegate).isEmpty }
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(next))
        manager.destroyWebView()
    }

    func testSameTokenAfterIdentityChangeIsDeliveredAgain() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("same")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let updates = await authTokenManager.refreshes()
        await authTokenManager.registerProvider { token }
        try await fetchToken(from: authTokenManager)
        let (viewModel, delegate) = makeViewModel(authToken: token, authTokenManager: authTokenManager)
        let manager = IAFPresentationManager(viewController: nil)
        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: token,
            initialProfile: profileA,
            updates: updates,
            from: authTokenManager
        )
        manager.startTokenDelivery()
        await Task.yield()
        XCTAssertTrue(jwtScripts(delegate).isEmpty)

        IdentityStore.shared.update(profileB)
        await authTokenManager.clearTokenState()
        try await fetchToken(from: authTokenManager)

        await assertEventually { !self.jwtScripts(delegate).isEmpty }
        await Task.yield()
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(token))
        manager.destroyWebView()
    }

    func testTokenClearedBeforeDeliveryIsNeverWritten() async throws {
        IdentityStore.shared.update(profileA)
        let stale = try makeToken("stale")
        let fresh = try makeToken("fresh")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment() == 1 ? stale : fresh
        }
        try await fetchToken(from: authTokenManager)
        IdentityStore.shared.update(profileB)
        await authTokenManager.clearTokenState()
        let (viewModel, delegate) = makeViewModel(authToken: nil, authTokenManager: authTokenManager)
        let manager = IAFPresentationManager(viewController: nil)
        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: nil,
            initialProfile: profileB,
            updates: updates,
            from: authTokenManager
        )
        manager.startTokenDelivery()

        try await fetchToken(from: authTokenManager)

        await assertEventually { !self.jwtScripts(delegate).isEmpty }
        await Task.yield()
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(fresh))
        XCTAssertFalse(jwtScripts(delegate).contains { $0.contains(stale) })
        manager.destroyWebView()
    }

    func testIdentityChangedHook() {
        let anonymous = ProfileData(anonymousId: "anon-1")
        let identified = ProfileData(email: "a@example.com", anonymousId: "anon-1")
        let emailChanged = ProfileData(email: "b@example.com", anonymousId: "anon-1")

        let phoneAdded = ProfileData(
            email: "a@example.com",
            phoneNumber: "+15555550100",
            anonymousId: "anon-2"
        )

        XCTAssertTrue(IAFPresentationManager.identityChanged(from: identified, to: emailChanged))
        XCTAssertTrue(IAFPresentationManager.identityChanged(from: anonymous, to: identified))
        XCTAssertTrue(IAFPresentationManager.identityChanged(from: identified, to: nil))
        XCTAssertFalse(IAFPresentationManager.identityChanged(from: identified, to: phoneAdded))
        XCTAssertFalse(IAFPresentationManager.identityChanged(from: identified, to: identified))
        XCTAssertFalse(IAFPresentationManager.identityChanged(from: nil, to: identified))
        XCTAssertFalse(IAFPresentationManager.identityChanged(from: nil, to: nil))
    }

    func testDestroyWebViewStopsPendingAndRunningDelivery() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("token")
        let authTokenManager = makeUnboundedAuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let release = Latch()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment()
            await release.wait()
            return token
        }
        try await waitForProviderCalls(counter, atLeast: 1)
        let (viewModel, delegate) = makeViewModel(authToken: nil, authTokenManager: authTokenManager)
        let manager = IAFPresentationManager(viewController: nil)
        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: nil,
            initialProfile: IdentityStore.shared.current,
            updates: updates,
            from: authTokenManager
        )

        manager.destroyWebView()
        manager.startTokenDelivery()
        await release.open()
        try await fetchToken(from: authTokenManager)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(jwtScripts(delegate).isEmpty)
    }

    // MARK: - refreshJwt

    func testRefreshJwtPushesReplacementToLiveWebViewOnce() async throws {
        let rejected = try makeToken("rejected")
        let replacement = try makeToken("replacement")
        let sentinel = try makeToken("sentinel")
        let counter = InvocationCounter()
        let live = try await makeLiveWebView(showing: rejected) {
            switch await counter.increment() {
            case 1: return rejected
            case 2: return replacement
            default: return sentinel
            }
        }

        live.viewModel.receiveRefreshJwt()
        await assertEventually { !self.jwtScripts(live.delegate).isEmpty }
        await assertEventually { await !live.authTokenManager.isRefreshingRejectedTokenForTesting }
        let invocations = await counter.value
        XCTAssertEqual(invocations, 2, "expected exactly one provider call for the signal")

        live.viewModel.receiveRefreshJwt()
        await assertEventually { self.jwtScripts(live.delegate).contains { $0.contains(sentinel) } }

        let scripts = jwtScripts(live.delegate)
        XCTAssertEqual(scripts.count, 2, "the replacement must be pushed exactly once")
        XCTAssertTrue(scripts.first?.contains(replacement) == true)
        XCTAssertTrue(scripts.last?.contains(sentinel) == true)
        live.manager.destroyWebView()
    }

    func testRefreshJwtReturningTheRejectedTokenIsNotPushedAgain() async throws {
        let repeated = try makeToken("repeated")
        let sentinel = try makeToken("sentinel")
        let counter = InvocationCounter()
        let live = try await makeLiveWebView(showing: repeated) {
            await counter.increment() <= 2 ? repeated : sentinel
        }

        live.viewModel.receiveRefreshJwt()
        await assertEventually {
            let providerCalled = await counter.value >= 2
            let refreshing = await live.authTokenManager.isRefreshingRejectedTokenForTesting
            return providerCalled && !refreshing
        }
        let invocations = await counter.value
        XCTAssertEqual(invocations, 2, "expected exactly one provider call for the signal")

        live.viewModel.receiveRefreshJwt()

        await assertEventually { self.jwtScripts(live.delegate).contains { $0.contains(sentinel) } }
        XCTAssertEqual(jwtScripts(live.delegate).count, 1, "the repeated token must not be pushed again")
        live.manager.destroyWebView()
    }

    private struct LiveWebView {
        let manager: IAFPresentationManager
        let viewModel: IAFWebViewModel
        let delegate: MockIAFWebViewDelegate
        let authTokenManager: AuthTokenManager
    }

    /// Builds a live WebView showing `initialToken` for the current identity, with
    /// token delivery running from a fresh manager whose provider is `provider`.
    /// The provider's first call must return `initialToken`.
    private func makeLiveWebView(
        showing initialToken: String,
        provider: @escaping AuthTokenProvider
    ) async throws -> LiveWebView {
        IdentityStore.shared.update(profileA)
        let authTokenManager = makeUnboundedAuthTokenManager()
        await authTokenManager.registerProvider(provider)
        let warm = try await fetchToken(from: authTokenManager)
        XCTAssertEqual(warm.token, initialToken)
        let updates = await authTokenManager.refreshes()
        let (viewModel, delegate) = makeViewModel(
            authToken: initialToken, authTokenManager: authTokenManager
        )
        let manager = IAFPresentationManager(viewController: nil)
        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: initialToken,
            initialProfile: IdentityStore.shared.current,
            updates: updates,
            from: authTokenManager
        )
        manager.startTokenDelivery()
        return LiveWebView(
            manager: manager,
            viewModel: viewModel,
            delegate: delegate,
            authTokenManager: authTokenManager
        )
    }
}
