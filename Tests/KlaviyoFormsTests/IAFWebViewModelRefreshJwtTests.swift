//
//  IAFWebViewModelRefreshJwtTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import Combine
import WebKit
import XCTest

@MainActor
private final class RecordingWebViewDelegate: MockIAFWebViewDelegate {
    var onEvaluation: ((String) -> Void)?

    override func evaluateJavaScript(_ script: String) async throws -> Any? {
        let result = try await super.evaluateJavaScript(script)
        onEvaluation?(script)
        return result
    }

    func injectedTokens() -> [String] {
        evaluatedScripts.compactMap { script in
            guard script.hasPrefix(Self.setTokenPrefix) else { return nil }
            return String(script.dropFirst(Self.setTokenPrefix.count).dropLast(3))
        }
    }

    func removedToken() -> Bool {
        evaluatedScripts.contains("document.head.removeAttribute('data-klaviyo-jwt');")
    }

    private static let setTokenPrefix = "document.head.setAttribute('data-klaviyo-jwt', '"
}

@MainActor
final class IAFWebViewModelRefreshJwtTests: XCTestCase {
    private var manager: AuthTokenManager!
    private var counter: InvocationCounter!
    private var rejectedToken: String!
    private var replacementToken: String!

    override func setUp() async throws {
        try await super.setUp()
        manager = AuthTokenManager(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() }),
            currentDate: Date.init
        )
        counter = InvocationCounter()
        rejectedToken = try makeTestJWT(subject: "rejected")
        replacementToken = try makeTestJWT(subject: "replacement")
    }

    override func tearDown() async throws {
        await manager.unregisterProvider()
        manager = nil
        try await super.tearDown()
    }

    // MARK: - tests

    func testRefreshJwtInjectsReplacementIntoLiveWebView() async throws {
        try await registerProvider { [rejectedToken, replacementToken] invocation in
            try XCTUnwrap(invocation == 1 ? rejectedToken : replacementToken)
        }
        let (delegate, observation) = try await makeLiveSession()
        let model = delegate.viewModel
        defer { observation.cancel() }
        let injected = expectation(description: "replacement injected")
        delegate.onEvaluation = { [replacementToken] script in
            if let replacementToken, script.contains(replacementToken) { injected.fulfill() }
        }

        sendRefreshJwt(to: model)

        await fulfillment(of: [injected], timeout: 10)
        let invocations = await counter.value
        XCTAssertEqual(invocations, 2)
        XCTAssertEqual(delegate.injectedTokens(), [rejectedToken, replacementToken])
        XCTAssertEqual(model.authToken, replacementToken)
        XCTAssertFalse(delegate.removedToken())
    }

    func testRefreshJwtNeverReinjectsRejectedToken() async throws {
        try await registerProvider { [rejectedToken] _ in try XCTUnwrap(rejectedToken) }
        let (delegate, observation) = try await makeLiveSession()
        let model = delegate.viewModel
        defer { observation.cancel() }

        sendRefreshJwt(to: model)
        await model.rejectedAuthTokenRefresh?.value
        await awaitSentinelClear(on: delegate)

        let invocations = await counter.value
        XCTAssertEqual(invocations, 2)
        XCTAssertEqual(delegate.injectedTokens(), [rejectedToken])
    }

    func testRefreshJwtProviderFailureInjectsNothing() async throws {
        try await registerProvider { [rejectedToken] invocation in
            guard invocation == 1 else { throw TestProviderError.failed }
            return try XCTUnwrap(rejectedToken)
        }
        let (delegate, observation) = try await makeLiveSession()
        let model = delegate.viewModel
        defer { observation.cancel() }

        sendRefreshJwt(to: model)
        await model.rejectedAuthTokenRefresh?.value
        await awaitSentinelClear(on: delegate)

        let invocations = await counter.value
        XCTAssertEqual(invocations, 2)
        XCTAssertEqual(delegate.injectedTokens(), [rejectedToken])
    }

    func testRefreshJwtWithoutProviderInjectsNothing() async {
        let model = IAFWebViewModel(
            url: URL(fileURLWithPath: "/tmp/IAFWebViewModelRefreshJwtTests.html"),
            apiKey: "abc123",
            profileData: IdentityStore.shared.current,
            authToken: rejectedToken,
            authTokenManager: manager
        )
        let delegate = RecordingWebViewDelegate(viewModel: model)
        model.delegate = delegate
        var updates = await manager.updates().makeAsyncIterator()

        sendRefreshJwt(to: model)
        await model.rejectedAuthTokenRefresh?.value
        await manager.clearTokenState()

        let published = await publishedTokens(from: &updates, untilClears: 2)
        XCTAssertEqual(published, [])
        XCTAssertTrue(delegate.evaluatedScripts.isEmpty)
    }

    func testOverlappingRefreshJwtSignalsShareOneProviderCall() async throws {
        let providerRelease = Gate()
        let followUpToken = try makeTestJWT(subject: "follow-up")
        try await registerProvider { [rejectedToken, replacementToken] invocation in
            switch invocation {
            case 1: return try XCTUnwrap(rejectedToken)
            case 2:
                await providerRelease.wait()
                return try XCTUnwrap(replacementToken)
            default: return followUpToken
            }
        }
        let (delegate, observation) = try await makeLiveSession()
        let model = delegate.viewModel
        defer { observation.cancel() }
        let replacementInjected = expectation(description: "replacement injected")
        let followUpInjected = expectation(description: "follow-up injected")
        delegate.onEvaluation = { [replacementToken] script in
            if let replacementToken, script.contains(replacementToken) { replacementInjected.fulfill() }
            if script.contains(followUpToken) { followUpInjected.fulfill() }
        }

        sendRefreshJwt(to: model)
        let pendingRefresh = try XCTUnwrap(model.rejectedAuthTokenRefresh)
        sendRefreshJwt(to: model)
        XCTAssertEqual(model.rejectedAuthTokenRefresh, pendingRefresh)
        await counter.waitFor(atLeast: 2)
        await providerRelease.open()
        await pendingRefresh.value
        await fulfillment(of: [replacementInjected], timeout: 10)

        let invocations = await counter.value
        XCTAssertEqual(invocations, 2)
        XCTAssertEqual(delegate.injectedTokens(), [rejectedToken, replacementToken])

        sendRefreshJwt(to: model)
        await fulfillment(of: [followUpInjected], timeout: 10)
        let followUpInvocations = await counter.value
        XCTAssertEqual(followUpInvocations, 3)
    }

    func testRefreshCompletingAfterWebViewSessionEndsInjectsNothing() async throws {
        let providerRelease = Gate()
        try await registerProvider { [rejectedToken, replacementToken] invocation in
            if invocation == 1 { return try XCTUnwrap(rejectedToken) }
            await providerRelease.wait()
            return try XCTUnwrap(replacementToken)
        }
        let (delegate, observation) = try await makeLiveSession()
        let model = delegate.viewModel
        var updates = await manager.updates().makeAsyncIterator()
        _ = await updates.next()

        sendRefreshJwt(to: model)
        await counter.waitFor(atLeast: 2)
        observation.cancel()
        await providerRelease.open()
        await model.rejectedAuthTokenRefresh?.value
        await manager.clearTokenState()

        let published = await publishedTokens(from: &updates, untilClears: 1)
        XCTAssertEqual(published, [replacementToken])
        XCTAssertEqual(delegate.injectedTokens(), [rejectedToken])
        XCTAssertEqual(model.authToken, rejectedToken)
    }
}

// MARK: - Helpers

extension IAFWebViewModelRefreshJwtTests {
    private func registerProvider(
        _ token: @escaping @Sendable (_ invocation: Int) async throws -> String
    ) async throws {
        let counter = try XCTUnwrap(counter)
        await manager.registerProvider {
            let invocation = await counter.increment()
            return try await token(invocation)
        }
        _ = try await manager.currentToken(mode: .background)
    }

    /// Builds a WebView session wired to `manager` and waits until the cached
    /// token has been injected, so the session is subscribed before the test acts.
    private func makeLiveSession() async throws -> (RecordingWebViewDelegate, Task<Void, Never>) {
        let model = IAFWebViewModel(
            url: URL(fileURLWithPath: "/tmp/IAFWebViewModelRefreshJwtTests.html"),
            apiKey: "abc123",
            profileData: IdentityStore.shared.current,
            authTokenManager: manager
        )
        let delegate = RecordingWebViewDelegate(viewModel: model)
        model.delegate = delegate
        let injected = expectation(description: "cached token injected")
        delegate.onEvaluation = { [rejectedToken] script in
            if let rejectedToken, script.contains(rejectedToken) { injected.fulfill() }
        }
        let observation = model.observeAuthTokenUpdates()
        await fulfillment(of: [injected], timeout: 10)
        delegate.onEvaluation = nil
        return (delegate, observation)
    }

    /// Publishes a clear and waits for the session to apply it. Updates reach the
    /// session in order, so any replacement published earlier has been applied.
    private func awaitSentinelClear(on delegate: RecordingWebViewDelegate) async {
        let cleared = expectation(description: "sentinel clear applied")
        delegate.onEvaluation = { script in
            if script.contains("removeAttribute('data-klaviyo-jwt')") { cleared.fulfill() }
        }
        await manager.clearTokenState()
        await fulfillment(of: [cleared], timeout: 10)
    }

    private func publishedTokens(
        from updates: inout AsyncStream<AuthTokenUpdate>.Iterator,
        untilClears clears: Int
    ) async -> [String] {
        var tokens: [String] = []
        var seenClears = 0
        while seenClears < clears, let update = await updates.next() {
            switch update {
            case .cleared: seenClears += 1
            case let .token(token): tokens.append(token)
            }
        }
        return tokens
    }

    private func sendRefreshJwt(to model: IAFWebViewModel) {
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {"type":"refreshJwt","data":{}}
            """
        )
        model.handleScriptMessage(scriptMessage)
    }
}
