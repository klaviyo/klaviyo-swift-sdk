//
//  IAFDeepLinkEndToEndTests.swift
//  klaviyo-swift-sdk
//
//  MAGE-1070. Drives the full in-app forms deep link path in a real `WKWebView` on a
//  simulator: page JS posts the `openDeepLink` bridge message, the SDK decodes it,
//  dispatches through `EventDispatcher` and `DeepLinkManager`, and the host app's
//  registered deep link handler receives the URL.
//
//  Onsite is the only stubbed part. The local page posts the same payload shape that
//  fender `deepLinkToScreenAction.ts` emits for a "Go to app screen" CTA.
//
//  The scheme under test (`holafly`) is deliberately absent from the test bundle's
//  `CFBundleURLTypes`, so `UIApplication.shared.canOpenURL` returns false for it. That is
//  the customer's configuration, and it is what the removed gate used to reject.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
@testable import KlaviyoSwift
import WebKit
import XCTest

/// The production navigation policy calls `UIApplication.shared.open(_:)` for any URL that
/// is not the forms template, which would fire on our local `file://` page. Override it so
/// the test exercises the bridge without that side effect.
private class TestWebViewController: KlaviyoWebViewController {
    override func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        .allow
    }
}

final class IAFDeepLinkEndToEndTests: XCTestCase {
    private var viewModel: IAFWebViewModel!
    private var viewController: TestWebViewController!
    private var window: UIWindow!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        environment = KlaviyoEnvironment.test()
        seedCoreStores()

        // Route deep links through the production path rather than a spy left by another suite.
        DeepLinkManager.resetToProduction()

        // Instantiating the SDK registers `KlaviyoEventDispatcher` as the inbound dispatch target.
        _ = KlaviyoSDK()
    }

    @MainActor
    override func tearDown() async throws {
        KlaviyoSDK().unregisterDeepLinkHandler()
        DeepLinkManager.resetToProduction()
        window?.isHidden = true
        window = nil
        viewController = nil
        viewModel = nil
        try await super.tearDown()
    }

    /// End-to-end: a CTA tap in a real web view reaches the host app's deep link handler.
    /// Before the MAGE-1070 fix the `canOpenURL` gate dropped this silently.
    @MainActor
    func testFormDeepLinkReachesRegisteredHandlerThroughRealWebView() async throws {
        let expectedURL = try XCTUnwrap(
            URL(
                string: "holafly://notifications?utm_source=push_flow&utm_medium=push_notification&utm_campaign=test_inapp"
            )
        )

        // Premise: the scheme must be undeclared, or this passes without exercising the bug.
        XCTAssertFalse(
            UIApplication.shared.canOpenURL(expectedURL),
            "Premise broken: 'holafly' must not be in the test bundle's CFBundleURLTypes"
        )

        // Given - a host app deep link handler, the integration this bug bypassed
        let handlerCalled = expectation(description: "registered deep link handler invoked")
        var receivedURL: URL?
        KlaviyoSDK().registerDeepLinkHandler { url in
            receivedURL = url
            handlerCalled.fulfill()
        }

        // When - a real web view loads a page that posts the openDeepLink bridge message
        let fileURL = try XCTUnwrap(
            Bundle.module.url(forResource: "IAFDeepLinkEndToEnd", withExtension: "html")
        )
        let apiKey = try XCTUnwrap(SDKConfigStore.shared.current.apiKey)
        viewModel = IAFWebViewModel(
            url: fileURL,
            apiKey: apiKey,
            profileData: IdentityStore.shared.current
        )
        viewController = TestWebViewController(viewModel: viewModel)

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.loadViewIfNeeded()
        viewModel.delegate?.preloadUrl()

        // Then - the URL arrives at the host app's handler, query parameters intact
        await fulfillment(of: [handlerCalled], timeout: 10.0)
        XCTAssertEqual(receivedURL, expectedURL)
    }
}
