//
//  IAFWebViewModelPageAttributesTests.swift
//  klaviyo-swift-sdk
//
//  Loads the view model's load scripts into a real WKWebView and reads back what the page
//  sees on `document.head`, so the scripts are checked in the engine forms actually run in.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import WebKit
import XCTest

@MainActor
final class IAFWebViewModelPageAttributesTests: XCTestCase {
    private let trickyValue = #"o'brien "q" \ </script>"# + "\n\u{2028}@example.com"

    override class func setUp() {
        super.setUp()
        registerWithUIKitServicesOnMain()
    }

    override func setUp() async throws {
        try await super.setUp()
        seedCoreStores()
    }

    override func tearDown() async throws {
        IdentityStore.shared.reset()
        try await super.tearDown()
    }

    func testPageSeesEveryHeadAttributeUnchanged() async throws {
        let profile = ProfileData(email: trickyValue, externalId: "St. John's Lane")
        let viewModel = try IAFWebViewModel(
            url: XCTUnwrap(URL(string: "https://example.com")),
            apiKey: "abc123",
            profileData: profile,
            authToken: trickyValue
        )
        viewModel.initializeLoadScripts()
        let scripts = try XCTUnwrap(viewModel.loadScripts)
        let page = try await awaitBounded("page load") { try await PageLoader.load(scripts: scripts) }

        let head = try await page.headAttributes()
        XCTAssertEqual(
            try jsonObject(head["data-klaviyo-profile"]),
            try jsonObject(profile.toHtmlString())
        )
        XCTAssertEqual(head["data-klaviyo-jwt"], trickyValue)
        XCTAssertEqual(head["data-sdk-name"], environment.sdkName())
        XCTAssertEqual(head["data-sdk-version"], environment.sdkVersion())
        XCTAssertEqual(
            try jsonObject(head["data-native-bridge-handshake"]),
            try jsonObject(IAFNativeBridgeEvent.handshake)
        )
        // The load-time device script runs before `document.head` exists, so check the push path.
        let device = DeviceInfo(
            screen: .init(width: 402, height: 874),
            safeAreaInsets: .init(top: 47, bottom: 34, left: 0, right: 0),
            orientation: "portrait-primary",
            dpr: 3
        )
        _ = try await page.evaluate(device.asAttributeAssignmentScript())
        let pushed = try await page.headAttributes()["data-klaviyo-device"]
        XCTAssertEqual(try jsonObject(pushed), try jsonObject(device.toJsonString()))

        let src = try await page.evaluate("document.getElementById('klaviyoJS').src") as? String
        XCTAssertTrue(src?.contains("/onsite/js/klaviyo.js?company_id=abc123&env=in-app") == true, "\(src ?? "nil")")
    }

    private func jsonObject(_ json: String?) throws -> NSObject {
        let data = try Data(XCTUnwrap(json, "attribute missing").utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSObject)
    }
}

/// A WKWebView that loads a minimal page with the given user scripts installed.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    // A window keeps the web content process in the foreground; without one CI can stall the load.
    private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    private var finished: CheckedContinuation<Void, Error>?

    private init(scripts: Set<WKUserScript>) {
        let config = WKWebViewConfiguration()
        scripts.forEach(config.userContentController.addUserScript)
        webView = WKWebView(frame: window.bounds, configuration: config)
        super.init()
        window.addSubview(webView)
        window.isHidden = false
    }

    static func load(scripts: Set<WKUserScript>) async throws -> PageLoader {
        let page = PageLoader(scripts: scripts)
        page.webView.navigationDelegate = page
        try await withCheckedThrowingContinuation { continuation in
            page.finished = continuation
            page.webView.loadHTMLString("<!DOCTYPE html><html><head></head><body></body></html>", baseURL: nil)
        }
        return page
    }

    func headAttributes() async throws -> [String: String] {
        let script = "Object.fromEntries([...document.head.attributes].map(a => [a.name, a.value]))"
        return try await evaluate(script) as? [String: String] ?? [:]
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.resume()
        finished = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finished?.resume(throwing: error)
        finished = nil
    }
}
