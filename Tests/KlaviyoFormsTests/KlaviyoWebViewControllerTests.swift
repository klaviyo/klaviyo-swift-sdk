@testable import KlaviyoForms
@testable import KlaviyoSwift
import KlaviyoCore
import OSLog
import UIKit
import WebKit
import XCTest

/// A mock ``WKUserContentController`` that stores the removed script message handlers as a property.
///
/// When we try to deallocate an instance of a ``WKWebView``, we need to ensure that any ``WKScriptMessageHandler``s
/// assigned to its ``WKUserContentController`` get removed. If this doesn't happen, the ``WKWebView`` may not get
/// deallocated, and we will likely get a memory leak.
///
/// To unit test that the ``KlaviyoWebViewController`` successfully removes the script message handlers from
/// its ``WKWebView``'s ``WKUserContentController`` when the ``KlaviyoWebViewController`` gets
/// deallocated, we need a way to keep track of the message handlers that get removed. This class stores the removed
/// message handlers, so that we can `XCTAssert` that the removed message handlers are what we expect.
private final class MockWKUserContentController: WKUserContentController {
    var removedMessageHandlers = Set<String>()

    override func removeScriptMessageHandler(forName name: String) {
        removedMessageHandlers.insert(name)
        super.removeScriptMessageHandler(forName: name)
    }

    override func removeAllUserScripts() {
        userScripts.forEach { removedMessageHandlers.insert($0.description) }
        super.removeAllUserScripts()
    }
}

private final class MockIAFWebViewModel: KlaviyoWebViewModeling {
    var messageHandlers: Set<String>?

    var url: URL
    weak var delegate: KlaviyoWebViewDelegate?
    var loadScripts: Set<WKUserScript>?

    let formLifecycleStream: AsyncStream<IAFLifecycleEvent>
    private let formLifecycleContinuation: AsyncStream<IAFLifecycleEvent>.Continuation

    init(url: URL) {
        self.url = url
        let (stream, continuation) = AsyncStream.makeStream(of: IAFLifecycleEvent.self)
        formLifecycleStream = stream
        formLifecycleContinuation = continuation
    }

    func establishHandshake(timeout: TimeInterval) async throws {
        // Mock implementation - immediately succeeds
    }

    func waitForFormsDataLoaded(timeout: TimeInterval) async throws {
        // Mock implementation - immediately succeeds
    }

    func handleNavigationEvent(_ event: KlaviyoForms.WKNavigationEvent) {}
    func handleScriptMessage(_ message: WKScriptMessage) {}
}

final class KlaviyoWebViewControllerTests: XCTestCase {
    /// Test to validate that the ``KlaviyoWebViewController`` removes any script message handlers
    /// from its ``WKWebView``'s ``WKUserContentController`` when it gets deallocated.
    @MainActor
    func testScriptMessageHandlersAreRemovedOnDeallocation() async throws {
        // Given
        let config = WKWebViewConfiguration()
        let mockController = MockWKUserContentController()
        config.userContentController = mockController

        let url = URL(string: "https://www.google.com")!
        let viewModel = MockIAFWebViewModel(url: url)
        let messageHandlers = Set(["handler1", "handler2"])
        viewModel.messageHandlers = messageHandlers

        var viewController: KlaviyoWebViewController? = KlaviyoWebViewController(viewModel: viewModel) {
            WKWebView(frame: .zero, configuration: config)
        }

        // When
        viewController = nil

        // Then
        XCTAssertEqual(mockController.removedMessageHandlers, messageHandlers, "All message handlers should be removed when the KlaviyoWebViewController is deallocated")
    }
}

final class IAFWebViewModelScriptTests: XCTestCase {
    // MARK: - Properties

    private var config: WKWebViewConfiguration!
    private var viewModel: IAFWebViewModel!

    // MARK: - Setup

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Reset environment to clean state
        var testEnvironment = KlaviyoEnvironment.test()
        testEnvironment.sdkName = { "swift" }
        testEnvironment.sdkVersion = { "0.0.1" }
        testEnvironment.cdnURL = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "static.klaviyo.com"
            return components
        }
        environment = testEnvironment

        // Reset Klaviyo state
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

        // Create view model
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        let profileData = try await KlaviyoInternal.fetchProfileData()
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
        viewModel.initializeLoadScripts()

        // Create web view configuration
        config = WKWebViewConfiguration()
    }

    // MARK: - Helper Methods

    @MainActor
    private func createWebViewController() -> KlaviyoWebViewController {
        let viewController = KlaviyoWebViewController(viewModel: viewModel) {
            WKWebView(frame: .zero, configuration: self.config)
        }
        viewController.preloadUrl()
        return viewController
    }

    // MARK: - Tests

    @MainActor
    func testKlaviyoJsScriptIsAddedToWebView() async throws {
        // When
        _ = createWebViewController()
        let userScripts = config.userContentController.userScripts

        // Then
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("klaviyoJS") }), "Klaviyo JS script should be present in userContentController")
    }

    @MainActor
    func testSdkNameScriptIsAddedToWebView() async throws {
        // When
        _ = createWebViewController()
        let userScripts = config.userContentController.userScripts

        // Then
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("data-sdk-name") }), "SDK name script should be present in userContentController")
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("swift") }), "SDK name script should contain 'swift'")
    }

    @MainActor
    func testSdkVersionScriptIsAddedToWebView() async throws {
        // Given
        var testEnvironment = KlaviyoEnvironment.test()
        testEnvironment.sdkVersion = { "0.0.1" }
        environment = testEnvironment

        // Recreate view model with updated environment
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        let profileData = try await KlaviyoInternal.fetchProfileData()
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
        viewModel.initializeLoadScripts()

        // When
        _ = createWebViewController()
        let userScripts = config.userContentController.userScripts

        // Then
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("data-sdk-version") }), "SDK version script should be present in userContentController")
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("document.head.setAttribute('data-sdk-version', '0.0.1')") }), "SDK version script should contain the correct version")
    }

    @MainActor
    func testHandshakeScriptIsAddedToWebView() async throws {
        // When
        _ = createWebViewController()
        let userScripts = config.userContentController.userScripts

        // Then
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("data-native-bridge-handshake") }), "Handshake script should be present in userContentController")
    }

    @MainActor
    func testDataEnvironmentScriptIsAddedToWebView() async throws {
        // Given
        environment.formsDataEnvironment = { .web }

        // Recreate view model with updated environment
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        let profileData = try await KlaviyoInternal.fetchProfileData()
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
        viewModel.initializeLoadScripts()

        // When
        _ = createWebViewController()
        let userScripts = config.userContentController.userScripts

        // Then
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("data-forms-data-environment") }), "Data environment script should be present in userContentController")
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("web") }), "Data environment script should contain 'web'")
    }

    @MainActor
    func testProfileAttributesScriptIsAddedToWebView() async throws {
        // Given
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        let profileData = ProfileData(email: "test@example.com")
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
        viewModel.initializeLoadScripts()

        // When
        _ = createWebViewController()
        let userScripts = config.userContentController.userScripts

        // Then
        XCTAssertTrue(userScripts.contains(where: { $0.source.contains("data-klaviyo-profile") }), "Profile attributes script should be present in userContentController")
    }

    @MainActor
    func testScriptMessageHandlerDeduplication() async throws {
        // Given
        let viewController = createWebViewController()

        // When
        // Call configureLoadScripts multiple times (simulating multiple loadUrl calls)
        // This should not crash and should only add each handler once
        for _ in 0..<3 {
            viewController.preloadUrl()
        }

        // Then
        let userContentController = config.userContentController
        XCTAssertTrue(userContentController.userScripts.contains(where: { $0.source.contains("klaviyoJS") }), "Klaviyo JS script should be present")
        // Verify no crash occurred during multiple calls
        // If the deduplication wasn't working, this test would have crashed with NSInvalidArgumentException
    }
}
