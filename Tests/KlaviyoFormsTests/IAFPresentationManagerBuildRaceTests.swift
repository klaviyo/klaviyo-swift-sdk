//
//  IAFPresentationManagerBuildRaceTests.swift
//  klaviyo-swift-sdk
//
//  An identity replacement that lands while a webview is being built: the page must still
//  receive the incoming profile's token, after the profile it belongs to.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import XCTest

@MainActor
final class IAFPresentationManagerBuildRaceTests: XCTestCase {
    private let profileA = ProfileData(email: "a@example.com", anonymousId: "anon-1")
    private let profileB = ProfileData(email: "b@example.com", anonymousId: "anon-1")
    private var provider: ScriptedTokenProvider!
    private var authTokenManager: AuthTokenManager!
    private var presentationManager: IAFPresentationManager!

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        resetPresentationManagerStores()
        IdentityStore.shared.update(profileA)
        provider = ScriptedTokenProvider()
        authTokenManager = makeUnboundedAuthTokenManager()
        let provider = try XCTUnwrap(provider)
        await authTokenManager.registerProvider { try await provider.provide() }
        presentationManager = IAFPresentationManager(viewController: nil)
        presentationManager.indexHtmlFileUrl = try XCTUnwrap(
            Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html")
        )
        presentationManager.makeViewController = { InertWebViewController(hosting: $0) }
    }

    override func tearDown() async throws {
        presentationManager.destroyWebView()
        await authTokenManager.unregisterProvider()
        resetPresentationManagerStores()
        presentationManager = nil
        authTokenManager = nil
        provider = nil
        try await super.tearDown()
    }

    func testReplacementAfterInitialTokenFetchStillDeliversIncomingToken() async throws {
        presentationManager.fetchInitialAuthToken = { [profileB] authTokenManager in
            let refresh = try? await authTokenManager.currentTokenRefresh(mode: .background)
            IdentityStore.shared.update(profileB)
            return refresh
        }

        try await presentationManager.createFormWebViewAndListen(
            apiKey: "abc123",
            authTokenManager: authTokenManager
        )
        let viewModel = try XCTUnwrap(presentationManager.viewModel)
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        let mintedOutgoing = await provider.token(1)
        let outgoingToken = try XCTUnwrap(mintedOutgoing)
        let loadSources = viewModel.loadScripts?.map(\.source) ?? []
        XCTAssertEqual(viewModel.profileData, profileB)
        XCTAssertTrue(loadSources.contains { $0.contains(profileB.email ?? "") })
        XCTAssertFalse(loadSources.contains { $0.contains("data-klaviyo-jwt") })

        presentationManager.startTokenDelivery()
        await delegate.awaitScript(containing: "data-klaviyo-jwt")

        let mintedIncoming = await provider.token(2)
        let incomingToken = try XCTUnwrap(mintedIncoming)
        XCTAssertEqual(delegate.authTokenScripts.count, 1)
        XCTAssertFalse(delegate.evaluatedScripts.contains { $0.contains(outgoingToken) })
        let identityScripts = (viewModel.loadScripts?.map(\.source) ?? [])
            .filter { $0.contains("data-klaviyo-jwt") }
        XCTAssertEqual(identityScripts.count, 1)
        assertProfileBeforeToken(in: identityScripts, email: profileB.email ?? "", token: incomingToken)
        let invocations = await provider.invocationCount
        XCTAssertEqual(invocations, 2)
    }

    // MARK: - Helpers

    private func assertProfileBeforeToken(
        in scripts: [String],
        email: String,
        token: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lines = scripts.flatMap { $0.components(separatedBy: "\n") }
        let profileIndex = lines.firstIndex { $0.contains("data-klaviyo-profile") && $0.contains(email) }
        let tokenIndex = lines.firstIndex { $0.contains("data-klaviyo-jwt") && $0.contains(token) }
        guard let profileIndex, let tokenIndex else {
            XCTFail("expected a profile write and a token write", file: file, line: line)
            return
        }
        XCTAssertLessThan(profileIndex, tokenIndex, file: file, line: line)
    }
}
