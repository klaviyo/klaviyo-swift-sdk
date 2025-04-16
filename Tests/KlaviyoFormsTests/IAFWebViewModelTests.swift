//
//  IAFWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

@testable import KlaviyoCore
@testable import KlaviyoForms
import KlaviyoSwift
import WebKit
import XCTest

final class IAFWebViewModelTests: XCTestCase {
    // MARK: - setup

    var viewModel: IAFWebViewModel!
    var viewController: KlaviyoWebViewController!

    @MainActor
    override func setUp() async throws {
        // FIXME: refactor the KlaviyoUI test suite so we can use the TCA tools to initialize a test Klaviyo environment and set the Company ID, similar to how we do it here: https://github.com/klaviyo/klaviyo-swift-sdk/blob/c9bdf25e65a9c575d1e30216dcfcaa156c2ac60b/Tests/KlaviyoSwiftTests/StateManagementTests.swift#L29. Until we're able to do this, the apiKey in the test suite will be nil, and IAFWebViewModel.initializeLoadScripts() will return without injecting the required scripts. Once this is fixed, we should remove the `XCTSkipIf` line.
        try XCTSkipIf(
            KlaviyoInternal.apiKey == nil,
            "Skipping this test until the KlaviyoUI test suite is able to initialize a Company ID"
        )

        environment.appContextInfo = {
            AppContextInfo(executable: "", bundleId: "", appVersion: "", appBuild: "", appName: "", version: OperatingSystemVersion(majorVersion: 1, minorVersion: 2, patchVersion: 3), osName: "", manufacturer: "", deviceModel: "", deviceId: "", environment: "", klaviyoSdk: "swift", sdkVersion: "0.0.1")
        }
    }

    @MainActor
    func setupViewController() throws {
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, companyId: "abc123")
        viewController = KlaviyoWebViewController(viewModel: viewModel, webViewFactory: {
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

    // Helper method to check if we should skip the test
    @MainActor
    private func checkShouldSkipTest() async throws -> Bool {
        // Get the API key on the main actor
        var apiKey: String?
        await withCheckedContinuation { continuation in
            KlaviyoInternal.apiKey { key in
                apiKey = key
                continuation.resume()
            }
        }

        return apiKey == nil
    }

    // MARK: - html injection tests

    @MainActor
    func testInjectSdkNameAttribute() async throws {
        try setupViewController()

        // Check if we should skip this test
        if try await checkShouldSkipTest() {
            throw XCTSkip("Skipping this test until the KlaviyoUI test suite is able to initialize a Company ID")
        }

        // Check for CI environment
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        if isRunningOnCI {
            throw XCTSkip("Skipping test in Github CI environment")
        }

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

    @MainActor
    func testInjectSdkVersionAttribute() async throws {
        try setupViewController()
        // Check if we should skip this test
        if try await checkShouldSkipTest() {
            throw XCTSkip("Skipping this test until the KlaviyoUI test suite is able to initialize a Company ID")
        }

        // Check for CI environment
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        if isRunningOnCI {
            throw XCTSkip("Skipping test in Github CI environment")
        }

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

    @MainActor
    func testInjectHandshakeAttribute() async throws {
        try setupViewController()

        // Check if we should skip this test
        if try await checkShouldSkipTest() {
            throw XCTSkip("Skipping this test until the KlaviyoUI test suite is able to initialize a Company ID")
        }

        // Check for CI environment
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        if isRunningOnCI {
            throw XCTSkip("Skipping test in Github CI environment")
        }

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
            [{"type":"formWillAppear","version":1},{"type":"formDisappeared","version":1},{"type":"trackProfileEvent","version":1},{"type":"trackAggregateEvent","version":1},{"type":"openDeepLink","version":1},{"type":"abort","version":1}]
            """
        let expectedData = try XCTUnwrap(expectedHandshakeString.data(using: .utf8))
        let expectedHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: expectedData)

        let actualData = try XCTUnwrap(actualHandshakeString.data(using: .utf8))
        let actualHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: actualData)
        XCTAssertEqual(actualHandshakeData, expectedHandshakeData)
    }

    @MainActor
    func testInjectKlaviyoJsScript() async throws {
        try setupViewController()

        // Check if we should skip this test
        if try await checkShouldSkipTest() {
            throw XCTSkip("Skipping this test until the KlaviyoUI test suite is able to initialize a Company ID")
        }

        // Check for CI environment
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        if isRunningOnCI {
            throw XCTSkip("Skipping test in Github CI environment")
        }

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
}
