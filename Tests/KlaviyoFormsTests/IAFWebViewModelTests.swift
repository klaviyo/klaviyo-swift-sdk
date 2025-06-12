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
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - SDK Attribute Tests

    @MainActor
    func testInjectSdkNameAttribute() async throws {
        // When
        viewModel.initializeLoadScripts()
        let sdkNameScript = viewModel.findScript(containing: ["data-sdk-name", "swift"])

        // Then
        XCTAssertNotNil(sdkNameScript, "SDK name script should be injected")
    }

    @MainActor
    func testInjectSdkVersionAttribute() async throws {
        // When
        viewModel.initializeLoadScripts()
        let sdkVersionScript = viewModel.findScript(containing: ["data-sdk-version", "0.0.1"])

        // Then
        XCTAssertNotNil(sdkVersionScript, "SDK version script should be injected")
    }

    // MARK: - Environment Tests

    @MainActor
    func testInjectFormsDataEnvironmentAttribute() async throws {
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
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: nil)

        // When
        viewModel.initializeLoadScripts()
        let environmentScript = viewModel.findScript(containing: ["data-forms-data-environment", "web"])

        // Then
        XCTAssertNotNil(environmentScript, "Forms data environment script should be injected when set to web")
    }

    // MARK: - Handshake Tests

    @MainActor
    func testInjectHandshakeAttribute() async throws {
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
            [{"type":"formWillAppear","version":1},{"type":"formDisappeared","version":1},{"type":"trackProfileEvent","version":1},{"type":"trackAggregateEvent","version":1},{"type":"openDeepLink","version":2},{"type":"abort","version":1},{"type":"lifecycleEvent","version":1},{"type":"profileMutation","version":1}]
            """
        let expectedData = try XCTUnwrap(expectedHandshakeString.data(using: .utf8))
        let expectedHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: expectedData)

        let actualData = try XCTUnwrap(handshakeString.data(using: .utf8))
        let actualHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: actualData)
        XCTAssertEqual(actualHandshakeData, expectedHandshakeData)
    }

    // MARK: - Klaviyo JS Tests

    @MainActor
    func testInjectKlaviyoJsScript() async throws {
        // When
        viewModel.initializeLoadScripts()
        let klaviyoJsScript = viewModel.findScript(containing: ["klaviyoJS", "static.klaviyo.com/onsite/js/klaviyo.js"])

        // Then
        XCTAssertNotNil(klaviyoJsScript, "Klaviyo JS script should be injected")
        XCTAssertTrue(klaviyoJsScript?.source.contains("company_id=abc123") ?? false, "Script should include company ID")
        XCTAssertTrue(klaviyoJsScript?.source.contains("env=in-app") ?? false, "Script should include environment")
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

    @MainActor
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

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        lifecycleTask.cancel()
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
