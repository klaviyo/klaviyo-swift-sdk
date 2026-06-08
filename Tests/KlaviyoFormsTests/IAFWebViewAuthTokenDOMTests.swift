//
//  IAFWebViewAuthTokenDOMTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2026-06-08.
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import KlaviyoCore
import UIKit
import WebKit
import XCTest

/// Test subclass that allows all navigation. The production
/// `KlaviyoWebViewController.decidePolicyFor` opens any non-`InAppFormsTemplate.html`
/// URL via `UIApplication.shared.open`; the test loads `IAFUnitTest.html`, so this
/// override prevents an external-open attempt. It is the *only* deviation from
/// production and is orthogonal to JWT injection — webview creation,
/// `configureLoadScripts`, `evaluateJavaScript`, and delegate wiring are all
/// inherited unchanged.
private final class NavigationAllowingWebViewController: KlaviyoWebViewController {
    override func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        .allow
    }
}

/// Integration tests that validate the JWT lands in the DOM of the **production**
/// `WKWebView` — the one `KlaviyoWebViewController` creates and configures via its
/// own `configureLoadScripts()` — rather than a webview hand-built inside the test.
///
/// This mirrors the production object graph (`IAFPresentationManager.createFormWebView`):
/// a real `IAFWebViewModel(authToken:)` drives a real `KlaviyoWebViewController`,
/// which creates its own webview, registers the view model's load scripts on it,
/// and loads a document. We then read `document.head` back through the controller's
/// own `evaluateJavaScript`, so the assertion is against the webview the SDK would
/// actually present. Covers both the initial-load `WKUserScript` injection and the
/// live `pushAuthToken` refresh path (the controller is the view model's delegate,
/// so `pushAuthToken` evaluates JS against this same webview).
final class IAFWebViewAuthTokenDOMTests: XCTestCase {
    // MARK: - Properties

    /// Retains the window (and thus the controller + its webview) for the test's
    /// lifetime; placing the controller on a key window makes the webview load
    /// reliably.
    private var window: UIWindow?

    /// The webview the production controller created, captured via `webViewFactory`
    /// so the test can drive a completing load on it (see `makeLoadedController`).
    private var capturedWebView: WKWebView?

    private static let jwtAttributeRead = "document.head.getAttribute('data-klaviyo-jwt')"
    private static let sdkNameRead = "document.head.getAttribute('data-sdk-name')"

    // MARK: - Setup / teardown

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Mirror the established forms-suite setup so the view model and controller
        // build deterministically without hanging on real I/O.
        environment = KlaviyoEnvironment.test()
        environment.sdkName = { "swift" }
        environment.sdkVersion = { "0.0.1" }
        environment.cdnURL = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "static.klaviyo.com"
            return components
        }

        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()

        let testState = KlaviyoState(
            apiKey: "abc123",
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }
    }

    @MainActor
    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try await super.tearDown()
    }

    // MARK: - Initial-load injection (production WKUserScript path)

    @MainActor
    func testAuthTokenInjectedIntoProductionWebViewDOM() async throws {
        let token = "header.payload.signature"
        let (controller, _) = try await makeLoadedController(authToken: token)

        let injected = try await readJWT(controller)
        XCTAssertEqual(
            injected,
            token,
            "configureLoadScripts should set data-klaviyo-jwt on the controller's own webview DOM"
        )
    }

    @MainActor
    func testNoAuthTokenLeavesAttributeAbsentInProductionWebViewDOM() async throws {
        let (controller, _) = try await makeLoadedController(authToken: nil)

        let jwtValue = try await readJWT(controller)
        XCTAssertNil(jwtValue, "data-klaviyo-jwt must be absent when no token is set")

        // Sanity: a different production-assembled head attribute IS present, proving
        // configureLoadScripts ran on this webview — so the nil above is a true
        // absence, not a webview that simply failed to inject anything.
        let sdkName = try await controller.evaluateJavaScript(Self.sdkNameRead) as? String
        XCTAssertEqual(sdkName, "swift", "production load scripts should have run on this webview")
    }

    // MARK: - Live-refresh push (production pushAuthToken path)

    @MainActor
    func testPushAuthTokenUpdatesProductionWebViewDOM() async throws {
        let (controller, viewModel) = try await makeLoadedController(authToken: nil)

        let before = try await readJWT(controller)
        XCTAssertNil(before, "precondition: no token before a refresh is pushed")

        // The controller is the view model's delegate (set in its init), so this
        // evaluates JS against the controller's own webview — the production path.
        let refreshed = "header.refreshed.signature"
        await viewModel.pushAuthToken(refreshed)

        let after = try await readJWT(controller)
        XCTAssertEqual(
            after,
            refreshed,
            "pushAuthToken should update data-klaviyo-jwt on the production webview's live DOM"
        )
    }

    @MainActor
    func testPushAuthTokenAppliesUpdatesInOrderInProductionWebViewDOM() async throws {
        let (controller, viewModel) = try await makeLoadedController(authToken: nil)

        let first = "header.first.signature"
        let second = "header.second.signature"
        await viewModel.pushAuthToken(first)
        await viewModel.pushAuthToken(second)

        let value = try await readJWT(controller)
        XCTAssertEqual(value, second, "the last pushed token should win in the production webview's DOM")
    }

    // MARK: - Helpers

    /// Builds the production controller around a real `IAFWebViewModel`, lets it
    /// create and configure its own webview, then drives a completing document load
    /// so the production-registered load scripts actually execute. Returns once those
    /// scripts have run on the controller's webview.
    ///
    /// Why we don't rely on the controller's own `load(URLRequest(fileURL))`: under
    /// the test bundle's web-content sandbox that file load does not complete (it
    /// lands on an empty document), so the registered `.atDocumentEnd` user scripts
    /// never run. We therefore capture the controller's webview via `webViewFactory`
    /// — `configureLoadScripts()` still registers the real `viewModel.loadScripts` on
    /// it — and force a completing main-frame load via `loadHTMLString`. Only the
    /// document *delivery* differs from production; the injection wiring under test
    /// (controller → its webview's content controller) is the real one.
    @MainActor
    private func makeLoadedController(
        authToken: String?
    ) async throws -> (KlaviyoWebViewController, IAFWebViewModel) {
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: "abc123",
            profileData: nil,
            authToken: authToken
        )

        let controller = NavigationAllowingWebViewController(viewModel: viewModel) { [weak self] in
            let webView = Self.makeProductionLikeWebView()
            self?.capturedWebView = webView
            return webView
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible() // viewDidLoad → loadUrl → configureLoadScripts registers the scripts
        self.window = window

        // Force a completing load on the controller's own (now-configured) webview.
        let webView = try XCTUnwrap(capturedWebView, "webViewFactory should have captured the webview")
        webView.loadHTMLString("<html><head></head><body></body></html>", baseURL: nil)

        try await awaitProductionScriptsRan(controller)
        return (controller, viewModel)
    }

    /// A webview equivalent to the production `createDefaultWebView` (which is private).
    @MainActor
    private static func makeProductionLikeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: config)
    }

    /// Polls until the production load scripts have executed on the controller's
    /// webview. `data-sdk-name` is always part of `initializeLoadScripts`, so its
    /// presence is a reliable signal the registered scripts ran on the loaded
    /// document. The generous timeout absorbs first-load web-content-process spin-up.
    @MainActor
    private func awaitProductionScriptsRan(
        _ controller: KlaviyoWebViewController,
        timeout: TimeInterval = 30
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let sdkName = await (try? controller.evaluateJavaScript(Self.sdkNameRead)) as? String
            if sdkName == "swift" { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        XCTFail("production load scripts did not run within \(timeout)s")
    }

    @MainActor
    private func readJWT(_ controller: KlaviyoWebViewController) async throws -> String? {
        try await controller.evaluateJavaScript(Self.jwtAttributeRead) as? String
    }
}
