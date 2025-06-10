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

// Test-specific subclass that overrides navigation policy to allow all navigation
// This is required to get these unit tests to pass
private class TestKlaviyoWebViewController: KlaviyoWebViewController {
    override func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        .allow
    }
}

final class IAFWebViewModelTests: XCTestCase {
    // MARK: - setup

    var viewModel: IAFWebViewModel!
    private var viewController: TestKlaviyoWebViewController!

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

        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()

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

        // Now fetch profile data with clean state
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        let profileData = try await KlaviyoInternal.fetchProfileData()

        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))

        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
        viewController = TestKlaviyoWebViewController(viewModel: viewModel, webViewFactory: {
            let configuration = WKWebViewConfiguration()
            configuration.processPool = WKProcessPool() // Ensures a fresh WebKit process
            let webView = WKWebView(frame: .zero, configuration: configuration)
            return webView
        })
    }

    override func tearDown() {
        viewModel = nil
        viewController = nil

        super.tearDown()
    }

    // MARK: - html injection tests

    func testInjectSdkNameAttribute() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        try await viewModel.establishHandshake(timeout: 3.0)

        // When
        let script = "document.head.getAttribute('data-sdk-name');"
        let delegate = try XCTUnwrap(viewModel.delegate)
        let result = try await delegate.evaluateJavaScript(script)
        let resultString = try XCTUnwrap(result as? String)

        // Then
        XCTAssertEqual(resultString, "swift")
    }

    func testInjectSdkVersionAttribute() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        try await viewModel.establishHandshake(timeout: 3.0)

        // When
        let script = "document.head.getAttribute('data-sdk-version');"
        let delegate = try XCTUnwrap(viewModel.delegate)
        let result = try await delegate.evaluateJavaScript(script)
        let resultString = try XCTUnwrap(result as? String)

        // Then
        XCTAssertEqual(resultString, "0.0.1")
    }

    func testInjectFormsDataEnvironmentAttribute() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        try await viewModel.establishHandshake(timeout: 3.0)

        // When
        let script = "document.head.getAttribute('data-forms-data-environment');"
        let delegate = try XCTUnwrap(viewModel.delegate)
        let result = try await delegate.evaluateJavaScript(script)
        let resultString = result as? String

        // Then
        XCTAssertNil(resultString)
    }

    func testInjectFormsDataEnvironmentSetToWeb() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        environment.formsDataEnvironment = { .web }

        // Create a new viewModel with the updated environment
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        viewModel = await IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: nil)
        viewController = await TestKlaviyoWebViewController(viewModel: viewModel, webViewFactory: {
            let configuration = WKWebViewConfiguration()
            configuration.processPool = WKProcessPool() // Ensures a fresh WebKit process
            let webView = WKWebView(frame: .zero, configuration: configuration)
            return webView
        })

        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        try await viewModel.establishHandshake(timeout: 3.0)

        // When
        let script = "document.head.getAttribute('data-forms-data-environment');"
        let delegate = try XCTUnwrap(viewModel.delegate)
        let result = try await delegate.evaluateJavaScript(script)
        let resultString = try XCTUnwrap(result as? String)

        // Then
        XCTAssertEqual(resultString, "web")
    }

    func testInjectHandshakeAttribute() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        try await viewModel.establishHandshake(timeout: 3.0)

        // When
        let script = "document.head.getAttribute('data-native-bridge-handshake');"
        let delegate = try XCTUnwrap(viewModel.delegate)
        let result = try await delegate.evaluateJavaScript(script)
        let actualHandshakeString = try XCTUnwrap(result as? String)

        // Then
        struct TestableHandshakeData: Codable, Equatable {
            var type: String
            var version: Int
        }

        let expectedHandshakeString =
            """
            [{"type":"formWillAppear","version":1},{"type":"formDisappeared","version":1},{"type":"trackProfileEvent","version":1},{"type":"trackAggregateEvent","version":1},{"type":"openDeepLink","version":2},{"type":"abort","version":1},{"type":"lifecycleEvent","version":1},{"type":"profileMutation","version":1}]
            """
        let expectedData = try XCTUnwrap(expectedHandshakeString.data(using: .utf8))
        let expectedHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: expectedData)

        let actualData = try XCTUnwrap(actualHandshakeString.data(using: .utf8))
        let actualHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: actualData)
        XCTAssertEqual(actualHandshakeData, expectedHandshakeData)
    }

    func testInjectKlaviyoJsScript() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        try await viewModel.establishHandshake(timeout: 3.0)

        // When
        let script = "document.getElementById('klaviyoJS').getAttribute('src');"
        let delegate = try XCTUnwrap(viewModel.delegate)
        let result = try await delegate.evaluateJavaScript(script)
        let resultString = try XCTUnwrap(result as? String)

        // Then
        XCTAssertEqual(resultString, "https://static.klaviyo.com/onsite/js/klaviyo.js?company_id=abc123&env=in-app")
    }

    func testInjectLifecycleEventsScript() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        try await viewModel.establishHandshake(timeout: 3.0)

        // When
        let script = """
            (function() {
                let eventDetails = null;
                document.head.addEventListener('lifecycleEvent', function(e) {
                    eventDetails = e.detail;
                });
                window.dispatchLifecycleEvent('foreground');
                return eventDetails;
            })();
        """
        let delegate = try XCTUnwrap(viewModel.delegate)
        let result = try await delegate.evaluateJavaScript(script)
        let resultDict = try XCTUnwrap(result as? [String: Any])

        // Then
        XCTAssertEqual(resultDict["type"] as? String, "foreground", "Event type should be 'foreground'")
    }

    func testAbortEventYieldsAbortLifecycleEvent() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Abort event should yield abort lifecycle event")
        let abortReason = "test abort reason"

        // Create a task to listen for lifecycle events
        let lifecycleTask = Task {
            for await event in viewModel.formLifecycleStream {
                if case .abort = event {
                    expectation.fulfill()
                    break
                }
            }
        }

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

        await viewModel.handleScriptMessage(scriptMessage)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        lifecycleTask.cancel()
    }
}
