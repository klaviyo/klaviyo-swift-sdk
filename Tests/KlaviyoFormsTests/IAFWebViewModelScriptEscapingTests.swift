//
//  IAFWebViewModelScriptEscapingTests.swift
//  klaviyo-swift-sdk
//
//  Checks that profile and auth token values reach the page unchanged whatever
//  characters they contain, on a page that is loading and on a live page.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import WebKit
import XCTest

@MainActor
final class IAFWebViewModelScriptEscapingTests: XCTestCase {
    private let awkwardValues = [
        "o'brien@example.com",
        "say \"hi\"@example.com",
        #"back\slash@example.com"#,
        "line\nbreak@example.com",
        "ünï©ode😀@example.com",
        "separator\u{2028}\u{2029}@example.com",
        "</script>@example.com"
    ]
    private let awkwardToken = "tok'en\"with\\odd\nchars\u{2028}</script>"

    override func setUp() async throws {
        try await super.setUp()
        seedCoreStores()
    }

    override func tearDown() async throws {
        IdentityStore.shared.reset()
        try await super.tearDown()
    }

    func testLoadScriptSetsProfileAndTokenUnchanged() async throws {
        let page = try await makePage()
        for email in awkwardValues {
            let profile = ProfileData(email: email, externalId: email, anonymousId: "anon")
            let viewModel = IAFWebViewModel(
                url: URL(string: "https://example.com")!,
                apiKey: "abc123",
                profileData: profile,
                authToken: awkwardToken
            )
            let source = try XCTUnwrap(
                viewModel.loadScripts?.map(\.source).first { $0.contains("data-klaviyo-jwt") }
            )
            try await page.clearIdentityAttributes()

            try await page.evaluate(source)

            try await assertAttributes(of: page, profile: profile, token: awkwardToken, email)
        }
    }

    func testLivePageWritesSetProfileAndTokenUnchanged() async throws {
        let authTokenManager = makeUnboundedAuthTokenManager()
        let page = try await makePage()
        for email in awkwardValues {
            let profile = ProfileData(email: email, externalId: email, anonymousId: "anon")
            IdentityStore.shared.update(profile)
            let viewModel = IAFWebViewModel(
                url: URL(string: "https://example.com")!,
                apiKey: "abc123",
                profileData: nil,
                authTokenManager: authTokenManager
            )
            let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
            viewModel.delegate = delegate
            try await page.clearIdentityAttributes()

            await delegate.waitForScript(containing: "data-klaviyo-profile")
            await viewModel.pushAuthToken(
                awkwardToken,
                generation: authTokenManager.currentIdentityGeneration
            )
            for script in delegate.evaluatedScripts {
                try await page.evaluate(script)
            }

            try await assertAttributes(of: page, profile: profile, token: awkwardToken, email)
            IdentityStore.shared.reset()
        }
    }

    // MARK: - Helpers

    private func assertAttributes(
        of page: WKWebView,
        profile: ProfileData,
        token: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let profileValue = try await page.evaluate("document.head.getAttribute('data-klaviyo-profile')")
        let tokenValue = try await page.evaluate("document.head.getAttribute('data-klaviyo-jwt')")
        XCTAssertEqual(
            try jsonObject(profileValue as? String),
            try jsonObject(profile.toHtmlString()),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(tokenValue as? String, token, message, file: file, line: line)
    }

    private func jsonObject(_ json: String?) throws -> NSDictionary {
        let data = try Data(XCTUnwrap(json).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func makePage() async throws -> WKWebView {
        let page = WKWebView(frame: .zero)
        let loaded = NavigationWaiter()
        page.navigationDelegate = loaded
        page.loadHTMLString("<html><head></head><body></body></html>", baseURL: nil)
        try await loaded.finished(timeout: Self.pageLoadTimeout)
        return page
    }

    private static let pageLoadTimeout: TimeInterval = 45
}

private enum PageError: Error, CustomStringConvertible {
    case loadTimedOut(TimeInterval)
    case scriptFailed(script: String, underlying: Error)

    var description: String {
        switch self {
        case let .loadTimedOut(timeout):
            "The test page did not finish loading within \(timeout) seconds"
        case let .scriptFailed(script, underlying):
            "The page rejected a script (\(underlying)): \(script.debugDescription)"
        }
    }
}

private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private let loaded = XCTestExpectation(description: "test page load")
    private var failure: Error?

    func finished(timeout: TimeInterval) async throws {
        let result = await XCTWaiter.fulfillment(of: [loaded], timeout: timeout)
        if let failure { throw failure }
        guard result == .completed else { throw PageError.loadTimedOut(timeout) }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        loaded.fulfill()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        failure = error
        loaded.fulfill()
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        failure = error
        loaded.fulfill()
    }
}

extension WKWebView {
    fileprivate func clearIdentityAttributes() async throws {
        try await evaluate(
            "document.head.removeAttribute('data-klaviyo-profile');"
                + "document.head.removeAttribute('data-klaviyo-jwt');"
        )
    }

    @discardableResult
    fileprivate func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: PageError.scriptFailed(script: script, underlying: error))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
