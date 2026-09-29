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
        var bootstrapElapsed: TimeInterval?
        do {
            try await IAFPresentationManager.shared.createFormWebViewAndListen(
                apiKey: "abc123",
                startLifecycleListener: false,
                onBootstrapResolved: { bootstrapElapsed = ProcessInfo.processInfo.systemUptime - started }
            )
        } catch {
            await releaseProvider.open()
            throw error
        }
        await releaseProvider.open()

        XCTAssertLessThan(try XCTUnwrap(bootstrapElapsed), 1.2)
        XCTAssertFalse(try installedUserScripts().contains { $0.source.contains(token) })
    }

    func testBootstrapDeadlineIncludesPriorCommandAndLateTokenArrives() async throws {
        let profileReset = Task {
            _ = try? await Task.sleep(nanoseconds: 400_000_000)
        }
        AuthTokenCommandQueue.shared.enqueue(.clearTokenStateAfter(profileReset))
        let token = try makeFormsJWT(subject: "late")
        let releaseProvider = FormsTestGate()
        await AuthTokenManager.shared.registerProvider {
            await releaseProvider.wait()
            return token
        }

        let started = ProcessInfo.processInfo.systemUptime
        var bootstrapElapsed: TimeInterval?
        try await IAFPresentationManager.shared.createFormWebViewAndListen(
            apiKey: "abc123",
            startLifecycleListener: false,
            onBootstrapResolved: { bootstrapElapsed = ProcessInfo.processInfo.systemUptime - started }
        )
        XCTAssertLessThan(try XCTUnwrap(bootstrapElapsed), 0.8)
        XCTAssertFalse(try installedUserScripts().contains { $0.source.contains(token) })

        await releaseProvider.open()
        try await withTimeout(seconds: 2) {
            while try !self.installedUserScripts().contains(where: { $0.source.contains(token) }) {
                await Task.yield()
            }
        }
    }

    func testPendingResetPastDeadlineStartsWithoutOutgoingProfile() async throws {
        let stateA = KlaviyoState(
            apiKey: "abc123",
            email: "a@example.com",
            anonymousId: "anon-a",
            queue: [],
            initalizationState: .initialized
        )
        let stateB = KlaviyoState(
            apiKey: "abc123",
            email: "b@example.com",
            anonymousId: "anon-b",
            queue: [],
            initalizationState: .initialized
        )
        let subject = CurrentValueSubject<KlaviyoState, Never>(stateA)
        klaviyoSwiftEnvironment.statePublisher = { subject.eraseToAnyPublisher() }
        KlaviyoInternal.resetProfileDataSubject()
        let releaseReset = FormsTestGate()
        let reset = Task { @MainActor in
            await releaseReset.wait()
            subject.send(stateB)
        }
        let command = AuthTokenCommandQueue.shared.enqueue(.clearTokenStateAfter(reset))

        let started = ProcessInfo.processInfo.systemUptime
        var bootstrapElapsed: TimeInterval?
        try await IAFPresentationManager.shared.createFormWebViewAndListen(
            apiKey: "abc123",
            startLifecycleListener: false,
            onBootstrapResolved: { bootstrapElapsed = ProcessInfo.processInfo.systemUptime - started }
        )
        XCTAssertLessThan(try XCTUnwrap(bootstrapElapsed), 0.8)
        XCTAssertFalse(try installedUserScripts().contains { $0.source.contains("a@example.com") })
        XCTAssertFalse(try installedUserScripts().contains { $0.source.contains("b@example.com") })

        await releaseReset.open()
        await command.value
        try await withTimeout(seconds: 2) {
            while try !self.installedUserScripts().contains(where: { $0.source.contains("b@example.com") }) {
                await Task.yield()
            }
        }
        XCTAssertFalse(try installedUserScripts().contains { $0.source.contains("a@example.com") })
    }

    func testPublicResetWaitsForProfileResetBeforePairingNewToken() async throws {
        let tokenB = try makeFormsJWT(subject: "B")
        let stateA = KlaviyoState(
            apiKey: "abc123",
            email: "a@example.com",
            anonymousId: "anon-a",
            queue: [],
            initalizationState: .initialized
        )
        let stateB = KlaviyoState(
            apiKey: "abc123",
            email: "b@example.com",
            anonymousId: "anon-b",
            queue: [],
            initalizationState: .initialized
        )
        let subject = CurrentValueSubject<KlaviyoState, Never>(stateA)
        let releaseReset = FormsTestGate()
        let resetEntered = expectation(description: "reset reducer action observed")
        let bootstrapEntered = expectation(description: "bootstrap entered pending-command wait")
        klaviyoSwiftEnvironment.statePublisher = { subject.eraseToAnyPublisher() }
        klaviyoSwiftEnvironment.send = { action in
            guard action == .resetProfileWithQueuedAuthClear else { return nil }
            return Task { @MainActor in
                resetEntered.fulfill()
                await releaseReset.wait()
                subject.send(stateB)
            }
        }
        KlaviyoInternal.resetProfileDataSubject()

        let sdk = KlaviyoSDK()
        sdk.resetProfile()
        await fulfillment(of: [resetEntered], timeout: 2)
        sdk.registerAuthTokenProvider { tokenB }
        let bootstrap = Task {
            try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123", startLifecycleListener: false) {
                await AuthTokenCommandQueue.shared.waitForPendingCommands {
                    bootstrapEntered.fulfill()
                }
            }
        }
        await fulfillment(of: [bootstrapEntered], timeout: 2)
        await releaseReset.open()
        try await bootstrap.value

        let scripts = try installedUserScripts().map(\.source)
        XCTAssertFalse(scripts.contains { $0.contains("a@example.com") })
        XCTAssertTrue(scripts.contains { $0.contains("b@example.com") })
        XCTAssertTrue(scripts.contains { $0.contains(tokenB) })
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
        let profileFetchObserved = expectation(description: "profile fetch subscribed")
        profileFetchObserved.assertForOverFulfill = false
        klaviyoSwiftEnvironment.statePublisher = {
            profileFetchObserved.fulfill()
            return stateSubject.eraseToAnyPublisher()
        }
        KlaviyoInternal.resetProfileDataSubject()
        let bootstrap = Task {
            try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123", startLifecycleListener: false)
        }
        await fulfillment(of: [profileFetchObserved], timeout: 2)

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
        try await IAFPresentationManager.shared.createFormWebViewAndListen(apiKey: "abc123", startLifecycleListener: false)
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
