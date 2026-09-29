//
//  IAFWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import KlaviyoCore
import WebKit
import XCTest

@MainActor
private final class LocalHTMLWebViewDelegate: UIViewController, KlaviyoWebViewDelegate, WKNavigationDelegate {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    var onNavigationFinished: (() -> Void)?
    private let viewModel: IAFWebViewModel

    init(viewModel: IAFWebViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.frame = view.bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func preloadUrl() {
        refreshLoadScripts()
        loadHTML(marker: "first")
    }

    func makeVisible() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = self
        window.makeKeyAndVisible()
        return window
    }

    func loadHTML(marker: String) {
        webView.loadHTMLString(
            "<html><head><meta name='test-navigation' content='\(marker)'></head><body></body></html>",
            baseURL: nil
        )
    }

    func refreshLoadScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        viewModel.loadScripts?
            .filter { !$0.source.contains("script.id = 'klaviyoJS'") }
            .forEach(controller.addUserScript)
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        onNavigationFinished?()
    }
}

// Captures inbound commands dispatched through the Core `EventDispatcher` lane.
private final class SpyDispatcher: EventDispatching {
    private(set) var received: [InboundCommand] = []
    func dispatch(_ command: InboundCommand) { received.append(command) }
}

final class IAFWebViewModelTests: XCTestCase {
    // MARK: - Properties

    var viewModel: IAFWebViewModel!

    // MARK: - Setup

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Reset environment to clean state to avoid state persistence from other tests
        environment = KlaviyoEnvironment.test()
        environment.sdkName = { "swift" }
        environment.sdkVersion = { "0.0.1" }
        // Override CDN URL to return the expected production URL for tests
        environment.cdnURL = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "static.klaviyo.com"
            return components
        }

        seedCoreStores()

        // Reset klaviyoSwiftEnvironment state to clean test state with expected API key
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

        // Read the seeded config/identity from the canonical Core stores
        let apiKey = try XCTUnwrap(SDKConfigStore.shared.current.apiKey)
        let profileData = IdentityStore.shared.current

        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - SDK Attribute Tests

    @MainActor
    func testInjectSdkNameAttribute() {
        // When
        viewModel.initializeLoadScripts()
        let sdkNameScript = viewModel.findScript(containing: ["data-sdk-name", "swift"])

        // Then
        XCTAssertNotNil(sdkNameScript, "SDK name script should be injected")
    }

    @MainActor
    func testInjectSdkVersionAttribute() {
        // When
        viewModel.initializeLoadScripts()
        let sdkVersionScript = viewModel.findScript(containing: ["data-sdk-version", "0.0.1"])

        // Then
        XCTAssertNotNil(sdkVersionScript, "SDK version script should be injected")
    }

    // MARK: - Environment Tests

    @MainActor
    func testInjectFormsDataEnvironmentAttribute() {
        // When
        viewModel.initializeLoadScripts()
        let environmentScript = viewModel.findScript(containing: "data-forms-data-environment")

        // Then
        XCTAssertNil(environmentScript, "Forms data environment script should not be injected when not set")
    }

    @MainActor
    func testInjectFormsDataEnvironmentSetToWeb() async throws {
        // Given
        environment.formsDataEnvironment = { .web }

        // Create a new viewModel with the updated environment
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let apiKey = try XCTUnwrap(SDKConfigStore.shared.current.apiKey)
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: nil)

        // When
        viewModel.initializeLoadScripts()
        let environmentScript = viewModel.findScript(containing: ["data-forms-data-environment", "web"])

        // Then
        XCTAssertNotNil(environmentScript, "Forms data environment script should be injected when set to web")
    }

    // MARK: - Handshake Tests

    @MainActor
    func testInjectHandshakeAttribute() throws {
        // When
        viewModel.initializeLoadScripts()
        let handshakeScript = viewModel.findScript(containing: "data-native-bridge-handshake")

        // Then
        XCTAssertNotNil(handshakeScript, "Handshake script should be injected")

        // Extract the handshake string from the script source
        let scriptSource = handshakeScript?.source ?? ""
        let components = scriptSource.components(separatedBy: "'")
        guard components.count >= 2 else {
            XCTFail("Could not find handshake data in script")
            return
        }
        let handshakeString = components[components.count - 2]

        // Verify handshake data
        struct TestableHandshakeData: Codable, Equatable {
            var type: String
            var version: Int
        }

        let expectedHandshakeString =
            """
            [{"type":"formWillAppear","version":2},{"type":"formDisappeared","version":1},{"type":"trackProfileEvent","version":1},{"type":"trackAggregateEvent","version":1},{"type":"openDeepLink","version":3},{"type":"abort","version":1},{"type":"lifecycleEvent","version":1},{"type":"profileEvent","version":1},{"type":"profileMutation","version":1},{"type":"jwtMutation","version":1}]
            """
        let expectedData = try XCTUnwrap(expectedHandshakeString.data(using: .utf8))
        let expectedHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: expectedData)

        let actualData = try XCTUnwrap(handshakeString.data(using: .utf8))
        let actualHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: actualData)
        XCTAssertEqual(actualHandshakeData, expectedHandshakeData)
    }

    // MARK: - Auth Token Tests

    @MainActor
    func testInjectAuthTokenAttribute() async throws {
        // Given
        let dummyToken = "header.payload.signature"
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let apiKey = try XCTUnwrap(SDKConfigStore.shared.current.apiKey)
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: nil, authToken: dummyToken)

        // When
        viewModel.initializeLoadScripts()
        let authTokenScript = viewModel.findScript(containing: ["data-klaviyo-jwt", dummyToken])

        // Then
        XCTAssertNotNil(authTokenScript, "Auth token script should be injected when authToken is provided")
    }

    @MainActor
    func testAuthTokenScriptNotInjectedWhenTokenIsNil() {
        // When (default viewModel from setUp has authToken: nil)
        viewModel.initializeLoadScripts()
        let authTokenScript = viewModel.findScript(containing: "data-klaviyo-jwt")

        // Then
        XCTAssertNil(authTokenScript, "Auth token script should not be injected when authToken is nil")
    }

    // MARK: - Klaviyo JS Tests

    @MainActor
    func testInjectKlaviyoJsScript() {
        // When
        viewModel.initializeLoadScripts()
        let klaviyoJsScript = viewModel.findScript(containing: ["klaviyoJS", "static.klaviyo.com/onsite/js/klaviyo.js"])

        // Then
        XCTAssertNotNil(klaviyoJsScript, "Klaviyo JS script should be injected")
        XCTAssertTrue(klaviyoJsScript?.source.contains("company_id=abc123") ?? false, "Script should include company ID")
        XCTAssertTrue(klaviyoJsScript?.source.contains("env=in-app") ?? false, "Script should include environment")
    }

    // MARK: - Event Handling Tests

    @MainActor
    func testFormWillAppearYieldsPresentLifecycleEvent() async throws {
        // When - simulate a form will appear script message
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formWillAppear",
              "data": {
                "formId": "test123",
                "formName": "Test Form"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await assertLifecycleEvent("present", from: viewModel.formLifecycleStream) { event in
            if case .present = event { return true }
            return false
        }
    }

    @MainActor
    func testFormDisappearedYieldsDismissLifecycleEvent() async throws {
        // When - simulate a form disappeared script message with formId and formName
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formDisappeared",
              "data": {
                "formId": "dismiss123",
                "formName": "Dismiss Form"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await assertLifecycleEvent("dismiss", from: viewModel.formLifecycleStream) { event in
            if case .dismiss = event { return true }
            return false
        }
    }

    @MainActor
    func testFormWillAppearYieldsPresentEvenWithMissingMetadata() async throws {
        // When - simulate a formWillAppear with empty data (no formId/formName)
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formWillAppear",
              "data": {}
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then - .present should still be yielded
        await assertLifecycleEvent("present", from: viewModel.formLifecycleStream) { event in
            if case .present = event { return true }
            return false
        }
    }

    @MainActor
    func testFormDisappearedYieldsDismissEvenWithMissingMetadata() async throws {
        // When - simulate a formDisappeared with empty data
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formDisappeared",
              "data": {}
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then - .dismiss should still be yielded
        await assertLifecycleEvent("dismiss", from: viewModel.formLifecycleStream) { event in
            if case .dismiss = event { return true }
            return false
        }
    }

    @MainActor
    func testAbortEventYieldsAbortLifecycleEvent() async {
        // Given
        let abortReason = "test abort reason"

        // When - simulate an abort script message
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "abort",
              "data": {
                "reason": "\(abortReason)"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await assertLifecycleEvent("abort", from: viewModel.formLifecycleStream) { event in
            if case .abort = event { return true }
            return false
        }
    }

    // MARK: - External URL Tests (openDeepLink with openExternally: true)

    private func makeOpenExternalUrlMessage(
        url: String? = "https://example.com",
        formId: String? = "form123",
        formName: String? = "Newsletter",
        buttonLabel: String? = "Learn More"
    ) -> MockWKScriptMessage {
        // External web URLs ride the openDeepLink message with openExternally: true;
        // the URL is sent in the platform-split `ios`/`android` keys.
        var data: [String: String] = [:]
        data["ios"] = url
        data["android"] = url
        data["formId"] = formId
        data["formName"] = formName
        data["buttonLabel"] = buttonLabel
        let dataJson = data.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let dataBody = dataJson.isEmpty ? "\"openExternally\": true" : "\(dataJson), \"openExternally\": true"
        return MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: "{ \"type\": \"openDeepLink\", \"data\": { \(dataBody) } }"
        )
    }

    @MainActor
    func testHandleOpenExternalUrlFiresLifecycleEvent() async throws {
        // Given
        var receivedEvent: FormLifecycleEvent?
        IAFPresentationManager.shared.registerFormLifecycleHandler { event in
            receivedEvent = event
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // A spurious dispatch through EventDispatcher would mean the deep-link path ran
        // instead. IAFWebViewModel's deep-link branch calls EventDispatcher.shared.dispatch
        // synchronously (no Task), so checking immediately after is reliable — no race.
        let spyDispatcher = SpyDispatcher()
        EventDispatcher.shared.register(spyDispatcher)
        defer { EventDispatcher.shared.reset() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage())

        // Then — the handler path is synchronous, so assert immediately.
        // External URL clicks surface through the same formCtaClicked event as deep links.
        guard case let .formCtaClicked(formId, formName, buttonLabel, url) = receivedEvent else {
            XCTFail("Expected formCtaClicked, got \(String(describing: receivedEvent))")
            return
        }
        XCTAssertEqual(formId, "form123")
        XCTAssertEqual(formName, "Newsletter")
        XCTAssertEqual(buttonLabel, "Learn More")
        XCTAssertEqual(url, URL(string: "https://example.com"))
        XCTAssertTrue(
            spyDispatcher.received.isEmpty,
            "openExternally: true must not route through EventDispatcher's deep-link path"
        )
    }

    @MainActor
    func testHandleOpenExternalUrlWithoutFormMetadataSkipsLifecycleEvent() async throws {
        // Given
        var lifecycleEventFired = false
        IAFPresentationManager.shared.registerFormLifecycleHandler { _ in
            lifecycleEventFired = true
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage(formId: nil, formName: nil))

        // Then
        XCTAssertFalse(lifecycleEventFired, "Lifecycle event should not fire without form metadata")
    }

    @MainActor
    func testHandleOpenExternalUrlWithMissingUrlSkipsLifecycleEvent() async throws {
        // Given
        var lifecycleEventFired = false
        IAFPresentationManager.shared.registerFormLifecycleHandler { _ in
            lifecycleEventFired = true
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage(url: nil))

        // Then
        XCTAssertFalse(lifecycleEventFired, "Lifecycle event should not fire with nil URL")
    }

    @MainActor
    func testHandleOpenExternalUrlWithDisallowedSchemeSkipsLifecycleEvent() async throws {
        // Given
        var lifecycleEventFired = false
        IAFPresentationManager.shared.registerFormLifecycleHandler { _ in
            lifecycleEventFired = true
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage(url: "javascript://alert(1)"))

        // Then
        XCTAssertFalse(lifecycleEventFired, "Blocked scheme should skip navigation and lifecycle event")
    }

    @MainActor
    func testTrackProfileEventDispatchesCreateEvent() throws {
        // Given - a spy registered as the inbound-dispatch target
        let spyDispatcher = SpyDispatcher()
        EventDispatcher.shared.register(spyDispatcher)
        defer { EventDispatcher.shared.reset() }

        // When - JS sends a trackProfileEvent bridge message
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "trackProfileEvent",
              "data": {
                "metric": "Viewed Product",
                "foo": "bar"
              }
            }
            """
        )
        viewModel.handleScriptMessage(scriptMessage)

        // Then - it routes through the EventDispatcher lane as .createEvent (no KlaviyoSwift dependency)
        guard spyDispatcher.received.count == 1 else {
            return XCTFail("expected 1 command, got \(spyDispatcher.received.count)")
        }
        guard case let .createEvent(event) = spyDispatcher.received[0] else {
            return XCTFail("expected .createEvent, got \(spyDispatcher.received[0])")
        }
        XCTAssertEqual(event.metric.name, .customEvent("Viewed Product"))
        XCTAssertEqual(event.properties["foo"] as? String, "bar")
    }

    // MARK: - Token Refresh Tests

    @MainActor
    func testPushAuthTokenUpdatesWebView() async throws {
        // Given — a view model with a wired-up delegate
        let (viewModel, delegate) = try makeTokenViewModel()

        // When — a refreshed token is pushed (driven by the presentation
        // manager's refresh subscription in production)
        let refreshedToken = "header.refreshed.signature"
        await viewModel.pushAuthToken(refreshedToken)

        // Then — it is applied as a data-klaviyo-jwt update carrying the token
        let script = try XCTUnwrap(tokenScripts(delegate).first)
        XCTAssertTrue(script.contains(refreshedToken), "Pushed token should update data-klaviyo-jwt with the new value")
    }

    @MainActor
    func testPushAuthTokenAppliesUpdatesInOrder() async throws {
        // Given
        let (viewModel, delegate) = try makeTokenViewModel()

        // When — two tokens are pushed sequentially
        let firstToken = "header.first.signature"
        let secondToken = "header.second.signature"
        await viewModel.pushAuthToken(firstToken)
        await viewModel.pushAuthToken(secondToken)

        // Then — both are applied, in order
        let scripts = tokenScripts(delegate)
        XCTAssertEqual(scripts.count, 2)
        XCTAssertTrue(scripts[0].contains(firstToken))
        XCTAssertTrue(scripts[1].contains(secondToken))
    }

    @MainActor
    func testClearAuthTokenRemovesLiveAttributeAndNextNavigationScript() async throws {
        let token = "header.outgoing.signature"
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let model = IAFWebViewModel(url: fileUrl, apiKey: "abc123", profileData: nil, authToken: token)
        let delegate = MockIAFWebViewDelegate(viewModel: model)
        model.delegate = delegate
        XCTAssertNotNil(model.findScript(containing: token))

        await model.clearAuthToken()

        XCTAssertNil(model.findScript(containing: token))
        XCTAssertTrue(tokenScripts(delegate).contains("document.head.removeAttribute('data-klaviyo-jwt');"))
    }

    @MainActor
    func testClearAuthTokenRemovesJWTFromLiveDOMAndNextNavigation() async throws {
        let token = "header.outgoing.signature"
        let pageURL = try XCTUnwrap(URL(string: "about:blank"))
        let model = IAFWebViewModel(url: pageURL, apiKey: "abc123", profileData: nil, authToken: token)
        let controller = LocalHTMLWebViewDelegate(viewModel: model)
        model.delegate = controller
        let window = controller.makeVisible()
        defer { window.isHidden = true }
        let jwtAttribute = "document.head.getAttribute('data-klaviyo-jwt')"
        let initialLoaded = expectation(description: "initial local document loaded")
        controller.onNavigationFinished = { initialLoaded.fulfill() }
        controller.preloadUrl()
        guard await XCTWaiter.fulfillment(of: [initialLoaded], timeout: 20) == .completed else {
            XCTFail("Initial local document did not load")
            return
        }
        let initialJWT = await readDOMString(jwtAttribute, in: controller.webView)
        XCTAssertEqual(initialJWT, token)

        let clearFinished = expectation(description: "live JWT removed")
        let clearTask = Task {
            await model.clearAuthToken()
            clearFinished.fulfill()
        }
        let clearResult = await XCTWaiter.fulfillment(of: [clearFinished], timeout: 10)
        clearTask.cancel()
        guard clearResult == .completed else {
            XCTFail("Live JWT removal did not complete")
            return
        }
        let clearedJWT = await readDOMString(jwtAttribute, in: controller.webView)
        XCTAssertNil(clearedJWT)
        XCTAssertFalse(
            controller.webView.configuration.userContentController.userScripts.contains {
                $0.source.contains(token)
            }
        )

        let nextLoaded = expectation(description: "next local document loaded")
        controller.onNavigationFinished = { nextLoaded.fulfill() }
        controller.loadHTML(marker: "second")
        let nextLoadResult = await XCTWaiter.fulfillment(of: [nextLoaded], timeout: 20)
        guard nextLoadResult == .completed else {
            XCTFail("Next local document did not load")
            return
        }
        let navigationMarker = await readDOMString(
            "document.head.querySelector('meta[name=\"test-navigation\"]')?.content",
            in: controller.webView
        )
        XCTAssertEqual(navigationMarker, "second")
        let nextJWT = await readDOMString(jwtAttribute, in: controller.webView)
        XCTAssertNil(nextJWT)
    }

    @MainActor
    private func readDOMString(_ script: String, in webView: WKWebView) async -> String? {
        let evaluated = expectation(description: "DOM evaluation completed")
        var value: String?
        webView.evaluateJavaScript(script) { result, error in
            XCTAssertNil(error)
            value = result as? String
            evaluated.fulfill()
        }
        await fulfillment(of: [evaluated], timeout: 10)
        return value
    }
}

extension IAFWebViewModel {
    @MainActor
    fileprivate func findScript(containing text: String) -> WKUserScript? {
        loadScripts?.first { script in
            script.source.contains(text)
        }
    }

    @MainActor
    fileprivate func findScript(containing texts: [String]) -> WKUserScript? {
        loadScripts?.first { script in
            texts.allSatisfy { text in
                script.source.contains(text)
            }
        }
    }
}

// MARK: - Token refresh test helpers

extension IAFWebViewModelTests {
    /// Builds a view model with a wired-up mock delegate, so `pushAuthToken`
    /// tests can observe the resulting `evaluateJavaScript` calls.
    @MainActor
    private func makeTokenViewModel() throws -> (IAFWebViewModel, MockIAFWebViewDelegate) {
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let viewModel = IAFWebViewModel(url: fileUrl, apiKey: "abc123", profileData: nil)
        let delegate = MockIAFWebViewDelegate(viewModel: viewModel)
        viewModel.delegate = delegate
        return (viewModel, delegate)
    }

    /// The auth-token update scripts among everything the delegate has evaluated.
    /// Filters out the incidental `data-klaviyo-profile` updates that the view
    /// model's profile subscription emits during setup, isolating the
    /// token-update behavior under test.
    @MainActor
    private func tokenScripts(_ delegate: MockIAFWebViewDelegate) -> [String] {
        delegate.evaluatedScripts.filter { $0.contains("data-klaviyo-jwt") }
    }
}
