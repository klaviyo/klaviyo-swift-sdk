//
//  IAFWebViewModelBadJWTTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import KlaviyoCore
import WebKit
import XCTest

@MainActor
final class IAFWebViewModelBadJWTTests: XCTestCase {
    // MARK: - setup

    var viewModel: IAFWebViewModel!
    var delegate: MockIAFWebViewDelegate!

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
        await expectNoAdditionalPushes(beyond: 2, timeout: 0.5)
        XCTAssertEqual(
            tokenScripts().count, 2,
            "BadJWT retries should be bounded, not one push per rejection"
        )

        await AuthTokenManager.shared.unregisterProvider()
    }

    func testBadJWTWithNoProviderRegisteredDoesNotPushOrCrash() async {
        // Given — no auth token provider registered
        await AuthTokenManager.shared.unregisterProvider()

        // When
        sendBadJWT()

        // Then — no crash, and nothing is pushed since there's no token to fetch
        await expectNoAdditionalPushes(beyond: 0, timeout: 0.5)
        XCTAssertTrue(tokenScripts().isEmpty)
    }
}

// MARK: - Helpers

extension IAFWebViewModelBadJWTTests {
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
    private func tokenScripts() -> [String] {
        delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }
    }

    /// Polls `condition` until it returns `true` or `timeout` elapses. Used for
    /// work kicked off by a fire-and-forget `Task` (like `.badJWT` handling)
    /// that isn't otherwise directly awaitable from the test.
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

    /// Asserts no further token pushes land beyond `count` within `timeout`,
    /// via an inverted `XCTestExpectation` rather than a fixed sleep — a
    /// regression is caught (and the wait ends) as soon as an extra push
    /// appears, instead of only being checked after always waiting out a
    /// fixed delay.
    private func expectNoAdditionalPushes(beyond count: Int, timeout: TimeInterval) async {
        let noExcessPush = XCTestExpectation(description: "no token push beyond \(count)")
        noExcessPush.isInverted = true
        let watcher = Task {
            while !Task.isCancelled {
                if tokenScripts().count > count {
                    noExcessPush.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        await fulfillment(of: [noExcessPush], timeout: timeout)
        watcher.cancel()
    }
}
