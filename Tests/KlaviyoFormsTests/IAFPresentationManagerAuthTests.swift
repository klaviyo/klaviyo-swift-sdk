//
//  IAFPresentationManagerAuthTests.swift
//  KlaviyoFormsTests
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import WebKit
import XCTest

@MainActor
final class IAFPresentationManagerAuthTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
        let state = KlaviyoState(
            apiKey: "abc123",
            anonymousId: "anon",
            queue: [],
            initalizationState: .initialized
        )
        let stateSubject = CurrentValueSubject<KlaviyoState, Never>(state)
        klaviyoSwiftEnvironment.statePublisher = { stateSubject.eraseToAnyPublisher() }
    }

    override func tearDown() async throws {
        IAFPresentationManager.shared.destroyWebviewAndListeners()
        await AuthTokenManager.shared.unregisterProvider()
    }

    func testBootstrapDoesNotWaitForInteractiveTokenTimeout() async throws {
        let token = try makeFormsJWT(subject: "initial")
        let providerEntered = FormsTestGate()
        let releaseProvider = FormsTestGate()
        let templateURL = IAFPresentationManager.shared.indexHtmlFileUrl
        IAFPresentationManager.shared.indexHtmlFileUrl = nil
        defer { IAFPresentationManager.shared.indexHtmlFileUrl = templateURL }
        await AuthTokenManager.shared.registerProvider {
            await providerEntered.open()
            await releaseProvider.wait()
            return token
        }
        await providerEntered.wait()

        do {
            try await withTimeout(seconds: 0.4) {
                try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")
            }
        } catch {
            await releaseProvider.open()
            throw error
        }

        XCTAssertNil(IAFPresentationManager.shared.viewController)
        await releaseProvider.open()
    }

    func testCachedTokenIsInstalledAsLoadScriptBeforeNavigation() async throws {
        let token = try makeFormsJWT(subject: "cached")
        await AuthTokenManager.shared.registerProvider { token }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)

        try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")

        let scripts = try installedUserScripts()
        let tokenScript = try XCTUnwrap(scripts.first { $0.source.contains(token) })
        let tokenIndex = try XCTUnwrap(scripts.firstIndex(of: tokenScript))
        let klaviyoIndex = try XCTUnwrap(scripts.firstIndex { $0.source.contains("klaviyoJS") })

        XCTAssertEqual(tokenScript.injectionTime, .atDocumentEnd)
        XCTAssertLessThan(tokenIndex, klaviyoIndex)
    }

    func testFastProviderCanPopulateLoadScriptDuringWebViewCreation() async throws {
        let token = try makeFormsJWT(subject: "cold-fast")
        let invocationCounter = FormsInvocationCounter()
        let cachePopulated = FormsTestGate()
        let profileSubscribed = FormsTestGate()
        await AuthTokenManager.shared.registerProvider {
            let invocation = await invocationCounter.next()
            if invocation == 2 {
                Task {
                    while await AuthTokenManager.shared.cachedTokenIfValid() != token {
                        await Task.yield()
                    }
                    await cachePopulated.open()
                }
            }
            return token
        }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)
        await AuthTokenManager.shared.clearTokenState()
        let state = KlaviyoState(
            apiKey: "abc123",
            anonymousId: "anon",
            queue: [],
            initalizationState: .initialized
        )
        let stateSubject = PassthroughSubject<KlaviyoState, Never>()
        klaviyoSwiftEnvironment.statePublisher = {
            stateSubject
                .handleEvents(receiveSubscription: { _ in
                    Task { await profileSubscribed.open() }
                })
                .eraseToAnyPublisher()
        }
        KlaviyoInternal.resetProfileDataSubject()

        let bootstrap = Task {
            try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")
        }
        try await withTimeout(seconds: 5) {
            await profileSubscribed.wait()
        }
        try await withTimeout(seconds: 5) {
            await cachePopulated.wait()
        }
        stateSubject.send(state)
        try await bootstrap.value

        let cachedToken = await AuthTokenManager.shared.cachedTokenIfValid()
        XCTAssertEqual(cachedToken, token)
        let scripts = try installedUserScripts()
        XCTAssertTrue(
            scripts.contains { $0.source.contains(token) },
            "Installed scripts: \(scripts.map(\.source))"
        )
    }

    func testPendingIdentityClearCannotPairNewProfileWithPreviousToken() async throws {
        let previousToken = try makeFormsJWT(subject: "previous")
        let currentToken = try makeFormsJWT(subject: "current")
        let tokenSource = FormsTokenSource(previousToken)
        await AuthTokenManager.shared.registerProvider { await tokenSource.value }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)
        await tokenSource.set(currentToken)

        let state = KlaviyoState(
            apiKey: "abc123",
            email: "current@example.com",
            anonymousId: "anon-current",
            queue: [],
            initalizationState: .initialized
        )
        let stateSubject = CurrentValueSubject<KlaviyoState, Never>(state)
        klaviyoSwiftEnvironment.statePublisher = { stateSubject.eraseToAnyPublisher() }
        KlaviyoInternal.resetProfileDataSubject()

        let previousRevision = AuthTokenCommandQueue.shared.revision
        AuthTokenCommandQueue.shared.enqueue(.clearTokenState)
        XCTAssertGreaterThan(AuthTokenCommandQueue.shared.revision, previousRevision)

        try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")

        let scripts = try installedUserScripts().map(\.source)
        XCTAssertFalse(scripts.contains { $0.contains(previousToken) })
        XCTAssertTrue(scripts.contains { $0.contains("current@example.com") })
    }

    private func installedUserScripts() throws -> [WKUserScript] {
        let viewController = try XCTUnwrap(IAFPresentationManager.shared.viewController)
        viewController.loadViewIfNeeded()
        let webView = try XCTUnwrap(viewController.view.subviews.compactMap { $0 as? WKWebView }.first)
        return webView.configuration.userContentController.userScripts
    }
}
