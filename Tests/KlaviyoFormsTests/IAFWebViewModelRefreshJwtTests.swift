//
//  IAFWebViewModelRefreshJwtTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import KlaviyoCore
import WebKit
import XCTest

@MainActor
final class IAFWebViewModelRefreshJwtTests: XCTestCase {
    // MARK: - setup

    private var authTokenManager: AuthTokenManager!
    private var viewModel: IAFWebViewModel!

    override func setUp() async throws {
        try await super.setUp()

        authTokenManager = makeIsolatedAuthTokenManager()
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: "abc123",
            profileData: nil,
            authTokenManager: authTokenManager
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        authTokenManager = nil
        try await super.tearDown()
    }

    // MARK: - tests

    func testRefreshJwtPublishesReplacementFromOneProviderCall() async throws {
        let rejected = try makeTestJWT(subject: "rejected")
        let replacement = try makeTestJWT(subject: "replacement")
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment() == 1 ? rejected : replacement
        }
        try await warmCache(expecting: rejected)
        let stream = await authTokenManager.refreshes()

        sendRefreshJwt()
        await awaitPendingRefresh()

        var iterator = stream.makeAsyncIterator()
        let delivered = await iterator.next()
        XCTAssertEqual(delivered, replacement)
        let invocations = await counter.value
        XCTAssertEqual(invocations, 2, "expected exactly one provider call for the signal")

        let served = try await authTokenManager.currentToken(mode: .background)
        XCTAssertEqual(served, replacement, "the rejected token must no longer be served")
        let invocationsAfterRead = await counter.value
        XCTAssertEqual(invocationsAfterRead, 2, "the replacement must be served from cache")
        XCTAssertNil(viewModel.pendingAuthTokenRefresh)
    }

    func testRefreshJwtRepublishesProviderTokenIdenticalToTheRejectedOne() async throws {
        let repeated = try makeTestJWT(subject: "repeated")
        let sentinel = try makeTestJWT(subject: "sentinel")
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await counter.increment() <= 2 ? repeated : sentinel
        }
        try await warmCache(expecting: repeated)
        let stream = await authTokenManager.refreshes()

        sendRefreshJwt()
        await awaitPendingRefresh()

        let invocations = await counter.value
        XCTAssertEqual(invocations, 2, "expected exactly one provider call for the signal")

        await authTokenManager.refreshRejectedToken()
        var iterator = stream.makeAsyncIterator()
        let delivered = await iterator.next()
        XCTAssertEqual(delivered, repeated, "a repeated token must be published, not swallowed")
    }

    func testOverlappingSignalsShareOneProviderCall() async throws {
        let rejected = try makeTestJWT(subject: "rejected")
        let replacement = try makeTestJWT(subject: "replacement")
        let sentinel = try makeTestJWT(subject: "sentinel")
        let counter = InvocationCounter()
        let fetchStarted = Latch()
        let releaseFetch = Latch()
        await authTokenManager.registerProvider {
            switch await counter.increment() {
            case 1:
                return rejected
            case 2:
                await fetchStarted.open()
                await releaseFetch.wait()
                return replacement
            default:
                return sentinel
            }
        }
        try await warmCache(expecting: rejected)
        let stream = await authTokenManager.refreshes()

        sendRefreshJwt()
        let firstRefresh = try XCTUnwrap(viewModel.pendingAuthTokenRefresh)
        await fetchStarted.wait()
        sendRefreshJwt()
        XCTAssertEqual(viewModel.pendingAuthTokenRefresh, firstRefresh, "the second signal must be dropped")

        await releaseFetch.open()
        await firstRefresh.value

        let invocations = await counter.value
        XCTAssertEqual(invocations, 2, "overlapping signals must share one provider call")
        var iterator = stream.makeAsyncIterator()
        let delivered = await iterator.next()
        XCTAssertEqual(delivered, replacement)
        await authTokenManager.refreshRejectedToken()
        let next = await iterator.next()
        XCTAssertEqual(next, sentinel, "overlapping signals must publish the replacement once")
    }

    func testSignalAfterCompletedRefreshStartsAnother() async throws {
        let tokens = try (1...3).map { try makeTestJWT(subject: "token-\($0)") }
        let counter = InvocationCounter()
        await authTokenManager.registerProvider {
            await tokens[min(counter.increment(), tokens.count) - 1]
        }
        try await warmCache(expecting: tokens[0])
        let stream = await authTokenManager.refreshes()

        sendRefreshJwt()
        await awaitPendingRefresh()
        sendRefreshJwt()
        await awaitPendingRefresh()

        let invocations = await counter.value
        XCTAssertEqual(invocations, 3)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        XCTAssertEqual([first, second], [tokens[1], tokens[2]])
    }
}

// MARK: - Helpers

extension IAFWebViewModelRefreshJwtTests {
    private func sendRefreshJwt() {
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {"type":"refreshJwt","data":{}}
            """
        )
        viewModel.handleScriptMessage(scriptMessage)
    }

    /// Waits for the eager warm-up fetch to cache `token`.
    private func warmCache(expecting token: String) async throws {
        let warm = try await authTokenManager.currentToken(mode: .background)
        XCTAssertEqual(warm, token)
    }

    private func awaitPendingRefresh() async {
        await viewModel.pendingAuthTokenRefresh?.value
    }
}
