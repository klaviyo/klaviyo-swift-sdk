@testable import KlaviyoForms
@testable import KlaviyoSwift
import KlaviyoCore
import WebKit
import XCTest

@MainActor
private final class TrackingUserContentController: WKUserContentController {
    private(set) var removalCount = 0

    override func removeAllUserScripts() {
        removalCount += 1
        super.removeAllUserScripts()
    }
}

@MainActor
private final class TrackingWebView: WKWebView {
    var simulatedLoading = false
    private(set) var loadCount = 0
    private(set) var stopCount = 0
    private(set) var evaluatedScripts: [String] = []
    var onEvaluation: ((String) -> Void)?

    override var isLoading: Bool { simulatedLoading }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadCount += 1
        simulatedLoading = true
        return nil
    }

    override func stopLoading() {
        stopCount += 1
        simulatedLoading = false
    }

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: ((Any?, Error?) -> Void)? = nil
    ) {
        evaluatedScripts.append(javaScriptString)
        onEvaluation?(javaScriptString)
        completionHandler?(nil, nil)
    }
}

final class IAFInitialNavigationAuthTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        seedCoreStores()
    }

    @MainActor
    func testIdenticalTokenReplayDoesNotChangeFirstNavigation() async {
        let (model, controller, webView, scripts) = makeController(initialToken: "outgoing")
        defer { withExtendedLifetime(controller) {} }
        let removals = scripts.removalCount

        await model.pushAuthToken("outgoing")

        XCTAssertEqual(webView.loadCount, 1)
        XCTAssertEqual(webView.stopCount, 0)
        XCTAssertEqual(scripts.removalCount, removals)
        XCTAssertFalse(webView.evaluatedScripts.contains { $0.contains("data-klaviyo-jwt") })
    }

    @MainActor
    func testClearDuringFirstNavigationRestartsWithoutOutgoingJWT() async {
        let (model, controller, webView, scripts) = makeController(initialToken: "outgoing")
        defer { withExtendedLifetime(controller) {} }

        await model.clearAuthToken()

        XCTAssertEqual(webView.stopCount, 1)
        XCTAssertEqual(webView.loadCount, 2)
        XCTAssertEqual(scripts.userScripts.filter { $0.source.contains("data-klaviyo-jwt") }.count, 0)
        XCTAssertEqual(scripts.userScripts.filter { $0.source.contains("data-native-bridge-handshake") }.count, 1)
        XCTAssertEqual(scripts.userScripts.filter { $0.source.contains("script.id = 'klaviyoJS'") }.count, 1)
    }

    @MainActor
    func testLateTokenDoesNotRestartFirstNavigationAndReachesLiveDOM() async {
        let (model, controller, webView, scripts) = makeController(initialToken: nil)
        defer { withExtendedLifetime(controller) {} }
        let applied = expectation(description: "late token applied after navigation")
        webView.onEvaluation = { script in
            if script.contains("data-klaviyo-jwt"), script.contains("late") {
                applied.fulfill()
            }
        }

        await model.pushAuthToken("late")

        XCTAssertEqual(webView.stopCount, 0)
        XCTAssertEqual(webView.loadCount, 1)
        XCTAssertFalse(webView.evaluatedScripts.contains { $0.contains("data-klaviyo-jwt") })

        webView.simulatedLoading = false
        controller.webView(webView, didFinish: nil)
        await fulfillment(of: [applied], timeout: 10)
        XCTAssertEqual(scripts.userScripts.filter { $0.source.contains("data-klaviyo-jwt") }.count, 1)
        XCTAssertEqual(scripts.userScripts.filter { $0.source.contains("data-native-bridge-handshake") }.count, 1)
    }

    @MainActor
    func testClearAfterPendingRefreshRestartsWithoutEitherToken() async {
        let (model, controller, webView, scripts) = makeController(initialToken: "outgoing")
        defer { withExtendedLifetime(controller) {} }

        await model.pushAuthToken("replacement")
        await model.clearAuthToken()

        XCTAssertEqual(webView.stopCount, 1)
        XCTAssertEqual(webView.loadCount, 2)
        XCTAssertFalse(scripts.userScripts.contains { $0.source.contains("data-klaviyo-jwt") })
        XCTAssertFalse(webView.evaluatedScripts.contains { $0.contains("data-klaviyo-jwt") })
    }

    @MainActor
    func testFailedFirstNavigationKeepsLatestTokenForNextNavigation() async {
        let (model, controller, webView, scripts) = makeController(initialToken: nil)
        await model.pushAuthToken("late")

        webView.simulatedLoading = false
        controller.webView(webView, didFail: nil, withError: URLError(.cancelled))

        XCTAssertEqual(scripts.userScripts.filter { $0.source.contains("data-klaviyo-jwt") }.count, 1)
        XCTAssertEqual(scripts.userScripts.filter { $0.source.contains("data-native-bridge-handshake") }.count, 1)
        XCTAssertEqual(webView.loadCount, 1)
    }

    @MainActor
    private func makeController(
        initialToken: String?
    ) -> (IAFWebViewModel, KlaviyoWebViewController, TrackingWebView, TrackingUserContentController) {
        let model = IAFWebViewModel(
            url: URL(fileURLWithPath: "/tmp/IAFInitialNavigationAuthTests.html"),
            apiKey: "abc123",
            profileData: nil,
            authToken: initialToken
        )
        let scripts = TrackingUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = scripts
        let webView = TrackingWebView(frame: .zero, configuration: configuration)
        let controller = KlaviyoWebViewController(viewModel: model) { webView }
        controller.preloadUrl()
        return (model, controller, webView, scripts)
    }
}
