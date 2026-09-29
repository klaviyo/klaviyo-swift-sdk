//
//  IAFPresentationManagerAuthBoundaryTests.swift
//  KlaviyoFormsTests
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import WebKit
import XCTest

@MainActor
final class IAFPresentationManagerAuthBoundaryTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
        let state = KlaviyoState(
            apiKey: "abc123",
            email: "a@example.com",
            anonymousId: "anon-a",
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

    func testBootstrapUsesOneTokenDeadline() async throws {
        let token = try makeFormsJWT(subject: "blocked")
        let providerEntered = FormsTestGate()
        let releaseProvider = FormsTestGate()
        await AuthTokenManager.shared.registerProvider {
            await providerEntered.open()
            await releaseProvider.wait()
            return token
        }
        await providerEntered.wait()

        let started = ProcessInfo.processInfo.systemUptime
        do {
            try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")
        } catch {
            await releaseProvider.open()
            throw error
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        await releaseProvider.open()

        XCTAssertLessThan(elapsed, 1.2)
        XCTAssertFalse(try installedUserScripts().contains { $0.source.contains(token) })
    }

    func testAuthCommandDuringBootstrapCannotPairOldTokenWithNewProfile() async throws {
        let tokenA = try makeFormsJWT(subject: "A")
        let tokenB = try makeFormsJWT(subject: "B")
        let providerEntered = FormsTestGate()
        let releaseProvider = FormsTestGate()
        await AuthTokenManager.shared.registerProvider {
            await providerEntered.open()
            await releaseProvider.wait()
            return tokenA
        }
        await providerEntered.wait()

        let stateA = KlaviyoState(
            apiKey: "abc123",
            email: "a@example.com",
            anonymousId: "anon-a",
            queue: [],
            initalizationState: .initialized
        )
        let stateSubject = CurrentValueSubject<KlaviyoState, Never>(stateA)
        klaviyoSwiftEnvironment.statePublisher = { stateSubject.eraseToAnyPublisher() }
        KlaviyoInternal.resetProfileDataSubject()
        let bootstrap = Task {
            try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        stateSubject.send(KlaviyoState(
            apiKey: "abc123",
            email: "b@example.com",
            anonymousId: "anon-b",
            queue: [],
            initalizationState: .initialized
        ))
        AuthTokenCommandQueue.shared.enqueue(.clearTokenState)
        AuthTokenCommandQueue.shared.enqueue(.register { tokenB })
        await releaseProvider.open()
        try await bootstrap.value

        let scripts = try installedUserScripts().map(\.source)
        XCTAssertFalse(scripts.contains { $0.contains(tokenA) })
        XCTAssertTrue(scripts.contains { $0.contains("b@example.com") })
    }

    func testBufferedTokenUpdateAfterInvalidationCannotRestoreOldToken() async throws {
        let token = try makeFormsJWT(subject: "old")
        await AuthTokenManager.shared.registerProvider { token }
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)
        try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123")
        let command = AuthTokenCommandQueue.shared.enqueue(.clearTokenState)
        await command.value

        await IAFPresentationManager.shared.applyTokenUpdate(.cleared)
        await IAFPresentationManager.shared.applyTokenUpdate(.token(token))

        XCTAssertFalse(try installedUserScripts().contains { $0.source.contains(token) })
    }

    private func installedUserScripts() throws -> [WKUserScript] {
        let viewController = try XCTUnwrap(IAFPresentationManager.shared.viewController)
        viewController.loadViewIfNeeded()
        let webView = try XCTUnwrap(viewController.view.subviews.compactMap { $0 as? WKWebView }.first)
        return webView.configuration.userContentController.userScripts
    }
}
