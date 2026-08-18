//
//  IAFWebViewModelBadJWTTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import KlaviyoCore
import WebKit
import XCTest

final class IAFWebViewModelBadJWTTests: XCTestCase {
    // MARK: - setup

    var viewModel: IAFWebViewModel!
    var delegate: MockIAFWebViewDelegate!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: "abc123", profileData: nil)
        delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
    }

    override func tearDown() {
        viewModel = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - tests

    @MainActor
    func testBadJWTFetchesFreshTokenAndPushesIt() async throws {
        // Given — a registered provider
        let freshToken = try makeTestJWT()
        await AuthTokenManager.shared.registerProvider { freshToken }

        // Let the eager warm-up fetch land first, so the assertion below
        // observes only the badJWT-triggered push.
        _ = try? await AuthTokenManager.shared.currentToken(mode: .background)

        // When — KlaviyoJS rejects the injected token
        sendBadJWT()

        // Then — a fresh token is fetched and pushed, resolving KlaviyoJS's
        // pending `awaitNextSetJWT()`
        try await waitUntil(timeout: 2.0) {
            tokenScripts().contains { $0.contains(freshToken) }
        }

        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    func testBadJWTRetryIsBoundedAfterRepeatedRejections() async throws {
        // Given — a provider whose warm-up invocation can be awaited deterministically
        let counter = InvocationCounter()
        await AuthTokenManager.shared.registerProvider {
            await counter.increment()
            return try makeTestJWT()
        }

        // Consume the eager warm-up invocation before triggering any retries
        await counter.waitFor(atLeast: 1)

        // When — badJWT fires more times than the retry limit allows
        for _ in 0..<5 {
            sendBadJWT()
        }

        // Then — only the bounded number of retry attempts push a token, not
        // one per rejection. Asserting on pushes rather than raw provider
        // invocations: two retries firing back-to-back can race inside
        // AuthTokenManager, with the second reusing the first's freshly
        // cached token instead of triggering its own fetch — a harmless
        // dedup, not a bug — so the push count is the stable signal here.
        try await waitUntil(timeout: 2.0) {
            tokenScripts().count == 2
        }
        try await Task.sleep(nanoseconds: 300_000_000) // let any excess retries (bug case) land
        XCTAssertEqual(
            tokenScripts().count, 2,
            "BadJWT retries should be bounded, not one push per rejection"
        )

        await AuthTokenManager.shared.unregisterProvider()
    }

    @MainActor
    func testBadJWTWithNoProviderRegisteredDoesNotPushOrCrash() async throws {
        // Given — no auth token provider registered
        await AuthTokenManager.shared.unregisterProvider()

        // When
        sendBadJWT()

        // Then — no crash, and nothing is pushed since there's no token to fetch
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(tokenScripts().isEmpty)
    }
}

// MARK: - Helpers

extension IAFWebViewModelBadJWTTests {
    @MainActor
    private func sendBadJWT() {
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {"type":"badJWT","data":{}}
            """
        )
        viewModel.handleScriptMessage(scriptMessage)
    }

    /// The auth-token update scripts among everything the delegate has evaluated.
    @MainActor
    private func tokenScripts() -> [String] {
        delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }
    }

    /// Polls `condition` until it returns `true` or `timeout` elapses. Used for
    /// work kicked off by a fire-and-forget `Task` (like `.badJWT` handling)
    /// that isn't otherwise directly awaitable from the test.
    @MainActor
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met within \(timeout) seconds")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
