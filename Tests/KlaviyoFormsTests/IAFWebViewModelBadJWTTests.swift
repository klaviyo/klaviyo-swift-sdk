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
        let refetched = expectation(description: "provider hit again after BadJWT")
        await AuthTokenManager.shared.registerProvider {
            let invocation = await counter.increment()
            if invocation == 2 {
                refetched.fulfill()
            }
            return try makeTestJWT()
        }

        // Consume the eager warm-up fetch, then confirm the cache is actually
        // serving that token without invoking the provider again.
        await counter.waitFor(atLeast: 1)
        _ = try await AuthTokenManager.shared.currentToken(mode: .background)
        let baseline = await counter.value
        XCTAssertEqual(baseline, 1, "Expected the cached token to be served without a new fetch")

        let cleared = expectation(description: "rejected token cleared")
        let observer = Task {
            let updates = await AuthTokenManager.shared.updates()
            for await update in updates {
                if case .cleared = update {
                    cleared.fulfill()
                    return
                }
            }
        }

        // When — KlaviyoJS rejects the injected token
        sendBadJWT()

        await fulfillment(of: [cleared], timeout: 30)
        observer.cancel()

        let probe = Task { _ = try? await AuthTokenManager.shared.currentToken(mode: .background) }
        await fulfillment(of: [refetched], timeout: 30)
        probe.cancel()

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
