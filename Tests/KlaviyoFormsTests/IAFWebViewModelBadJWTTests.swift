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

    override func setUp() async throws {
        try await super.setUp()

        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: "abc123", profileData: nil)
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - tests

    func testBadJWTInvalidatesCachedToken() async throws {
        // Given — a registered provider whose invocations can be counted deterministically
        let counter = InvocationCounter()
        await AuthTokenManager.shared.registerProvider {
            await counter.increment()
            return try makeTestJWT()
        }

        // Consume the eager warm-up fetch, then confirm the cache is actually
        // serving that token without invoking the provider again.
        await counter.waitFor(atLeast: 1)
        _ = try await AuthTokenManager.shared.currentToken()
        let baseline = await counter.value
        XCTAssertEqual(baseline, 1, "Expected the cached token to be served without a new fetch")

        // When — KlaviyoJS rejects the injected token
        sendBadJWT()

        // Then — the cache no longer serves the rejected token: the next
        // fetch must hit the provider again rather than reusing it. The
        // invalidation runs on a fire-and-forget Task, so poll for it.
        var refetched = false
        for _ in 0..<50 {
            _ = try? await AuthTokenManager.shared.currentToken()
            if await counter.value > baseline {
                refetched = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(
            refetched,
            "Expected badJWT to invalidate the cached token so the next fetch reaches the provider"
        )

        await AuthTokenManager.shared.unregisterProvider()
    }

    func testBadJWTWithNoProviderRegisteredDoesNotCrash() async {
        // Given — no auth token provider registered
        await AuthTokenManager.shared.unregisterProvider()

        // When / Then — no crash; clearing an already-empty cache is a no-op
        sendBadJWT()
        _ = try? await AuthTokenManager.shared.currentToken()
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
}
