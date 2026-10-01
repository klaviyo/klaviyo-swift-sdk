//
//  IAFPresentationManagerAuthTests.swift
//  klaviyo-swift-sdk
//
//  Auth token delivery to the live WebView: subscription ordering, handshake gating,
//  de-duplication and teardown.
//

@testable import KlaviyoForms
import KlaviyoCore
import XCTest

@MainActor
final class IAFPresentationManagerAuthTests: XCTestCase {
    private var fileUrl: URL!
    private let profileA = ProfileData(email: "a@example.com", anonymousId: "anon-1")
    private let profileB = ProfileData(email: "b@example.com", anonymousId: "anon-1")

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        IdentityStore.shared.reset()
        SDKConfigStore.shared.reset()
        seedCoreStores()
        fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
    }

    override func tearDown() async throws {
        IdentityStore.shared.reset()
        SDKConfigStore.shared.reset()
        try await super.tearDown()
    }

    private func makeToken(_ subject: String) throws -> String {
        try makeTestJWT(subject: subject, validAt: environment.date())
    }

    private func makeViewModel(authToken: String?) -> (IAFWebViewModel, MockIAFWebViewDelegate) {
        let viewModel = IAFWebViewModel(
            url: fileUrl, apiKey: "abc123", profileData: nil, authToken: authToken
        )
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        return (viewModel, delegate)
    }

    private func jwtScripts(_ delegate: MockIAFWebViewDelegate) -> [String] {
        delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("condition not met within \(timeout)s", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testProfileChangedDuringTokenWaitIsUsedForInitialDocument() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("token")
        let authTokenManager = AuthTokenManager()
        let counter = InvocationCounter()
        let profileB = profileB
        await authTokenManager.registerProvider {
            if await counter.increment() >= 2 {
                await MainActor.run { IdentityStore.shared.update(profileB) }
            }
            return token
        }
        _ = try await authTokenManager.currentToken(mode: .background)
        await authTokenManager.clearTokenState()
        let manager = IAFPresentationManager(viewController: nil)
        manager.indexHtmlFileUrl = fileUrl

        try await manager.createFormWebViewAndListen(apiKey: "abc123", authTokenManager: authTokenManager)

        XCTAssertEqual(manager.viewModel?.profileData, profileB)
        manager.destroyWebView()
    }

    func testTokenArrivingBeforeHandshakeIsHeldThenDelivered() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("late")
        let authTokenManager = AuthTokenManager()
        let updates = await authTokenManager.refreshes()
        await authTokenManager.registerProvider { token }
        _ = try await authTokenManager.currentToken(mode: .background)
        let (viewModel, delegate) = makeViewModel(authToken: nil)
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

        try await waitUntil { !self.jwtScripts(delegate).isEmpty }
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(token))
        manager.destroyWebView()
    }

    func testLateTokenReachesLiveWebViewOnce() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("late")
        let authTokenManager = AuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let release = Latch()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment()
            await release.wait()
            return token
        }
        await counter.waitFor(atLeast: 1)
        let (viewModel, delegate) = makeViewModel(authToken: nil)
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

        try await waitUntil { !self.jwtScripts(delegate).isEmpty }
        _ = try await authTokenManager.currentToken(mode: .background)
        await Task.yield()
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(token))
        manager.destroyWebView()
    }

    func testTokenAlreadyOnPageIsNotPushedAgainButNewTokenIs() async throws {
        IdentityStore.shared.update(profileA)
        let initial = try makeToken("initial")
        let next = try makeToken("next")
        let authTokenManager = AuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment() == 1 ? initial : next
        }
        _ = try await authTokenManager.currentToken(mode: .background)
        let (viewModel, delegate) = makeViewModel(authToken: initial)
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
        _ = try await authTokenManager.currentToken(mode: .background)

        try await waitUntil { !self.jwtScripts(delegate).isEmpty }
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(next))
        manager.destroyWebView()
    }

    func testSameTokenAfterIdentityChangeIsDeliveredAgain() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("same")
        let authTokenManager = AuthTokenManager()
        let updates = await authTokenManager.refreshes()
        await authTokenManager.registerProvider { token }
        _ = try await authTokenManager.currentToken(mode: .background)
        let (viewModel, delegate) = makeViewModel(authToken: token)
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
        _ = try await authTokenManager.currentToken(mode: .background)

        try await waitUntil { !self.jwtScripts(delegate).isEmpty }
        await Task.yield()
        XCTAssertEqual(jwtScripts(delegate).count, 1)
        XCTAssertTrue(jwtScripts(delegate)[0].contains(token))
        manager.destroyWebView()
    }

    func testTokenClearedBeforeDeliveryIsNeverWritten() async throws {
        IdentityStore.shared.update(profileA)
        let stale = try makeToken("stale")
        let fresh = try makeToken("fresh")
        let authTokenManager = AuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment() == 1 ? stale : fresh
        }
        _ = try await authTokenManager.currentToken(mode: .background)
        IdentityStore.shared.update(profileB)
        await authTokenManager.clearTokenState()
        let (viewModel, delegate) = makeViewModel(authToken: nil)
        let manager = IAFPresentationManager(viewController: nil)
        manager.prepareTokenDelivery(
            for: viewModel,
            initialToken: nil,
            initialProfile: profileB,
            updates: updates,
            from: authTokenManager
        )
        manager.startTokenDelivery()

        _ = try await authTokenManager.currentToken(mode: .background)

        try await waitUntil { !self.jwtScripts(delegate).isEmpty }
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

        XCTAssertTrue(IAFPresentationManager.identityChanged(from: identified, to: emailChanged))
        XCTAssertTrue(IAFPresentationManager.identityChanged(from: anonymous, to: identified))
        XCTAssertFalse(IAFPresentationManager.identityChanged(from: identified, to: identified))
        XCTAssertFalse(IAFPresentationManager.identityChanged(from: nil, to: nil))
    }

    func testDestroyWebViewStopsPendingAndRunningDelivery() async throws {
        IdentityStore.shared.update(profileA)
        let token = try makeToken("token")
        let authTokenManager = AuthTokenManager()
        let updates = await authTokenManager.refreshes()
        let release = Latch()
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment()
            await release.wait()
            return token
        }
        await counter.waitFor(atLeast: 1)
        let (viewModel, delegate) = makeViewModel(authToken: nil)
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
        _ = try await authTokenManager.currentToken(mode: .background)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(jwtScripts(delegate).isEmpty)
    }
}
