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

final class IAFPresentationManagerAuthTests: XCTestCase {
    @MainActor
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

    @MainActor
    override func tearDown() async throws {
        IAFPresentationManager.shared.destroyWebviewAndListeners()
        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    func testWebViewCreationDoesNotWaitForInteractiveTokenTimeout() async throws {
        let token = try makeFormsJWT(subject: "initial")
        let providerEntered = FormsTestGate()
        let releaseProvider = FormsTestGate()
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

        XCTAssertNotNil(IAFPresentationManager.shared.viewController)
        await releaseProvider.open()
    }

    @MainActor
    func testCachedTokenIsInstalledAsLoadScriptBeforeNavigation() async throws {
        let token = try makeFormsJWT(subject: "cached")
        await AuthTokenManager.shared.registerProvider { token }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)

        try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")

        let viewController = try XCTUnwrap(IAFPresentationManager.shared.viewController)
        viewController.loadViewIfNeeded()
        let webView = try XCTUnwrap(viewController.view.subviews.compactMap { $0 as? WKWebView }.first)
        let scripts = webView.configuration.userContentController.userScripts
        let tokenScript = try XCTUnwrap(scripts.first { $0.source.contains(token) })
        let tokenIndex = try XCTUnwrap(scripts.firstIndex(of: tokenScript))
        let klaviyoIndex = try XCTUnwrap(scripts.firstIndex { $0.source.contains("klaviyoJS") })

        XCTAssertEqual(tokenScript.injectionTime, .atDocumentEnd)
        XCTAssertLessThan(tokenIndex, klaviyoIndex)
    }

    @MainActor
    func testFastProviderCanPopulateLoadScriptDuringWebViewCreation() async throws {
        let token = try makeFormsJWT(subject: "cold-fast")
        let invocationCounter = FormsInvocationCounter()
        let cachePopulated = FormsBlockingGate()
        await AuthTokenManager.shared.registerProvider {
            let invocation = await invocationCounter.next()
            if invocation == 2 {
                Task {
                    while await AuthTokenManager.shared.cachedTokenIfValid() != token {
                        await Task.yield()
                    }
                    cachePopulated.open()
                }
            }
            return token
        }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)
        await AuthTokenManager.shared.clearTokenState()
        let statePublisher = klaviyoSwiftEnvironment.statePublisher
        klaviyoSwiftEnvironment.statePublisher = {
            XCTAssertTrue(cachePopulated.wait(timeout: 1))
            return statePublisher()
        }
        KlaviyoInternal.resetProfileDataSubject()

        try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")

        let viewController = try XCTUnwrap(IAFPresentationManager.shared.viewController)
        viewController.loadViewIfNeeded()
        let webView = try XCTUnwrap(viewController.view.subviews.compactMap { $0 as? WKWebView }.first)
        XCTAssertTrue(
            webView.configuration.userContentController.userScripts.contains { $0.source.contains(token) }
        )
    }
}
