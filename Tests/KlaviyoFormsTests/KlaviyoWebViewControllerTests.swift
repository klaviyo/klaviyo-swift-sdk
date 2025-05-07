@testable import KlaviyoForms
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

    init(url: URL) {
        self.url = url
    }

    func handleNavigationEvent(_ event: KlaviyoForms.WKNavigationEvent) {}
    func handleScriptMessage(_ message: WKScriptMessage) {}
    func handleViewTransition() {}
}

private final class MockIAFPresentationManager: IAFPresentationManager {
    var constructWebviewCalled = false
    var destroyWebviewCalled = false
    var dismissFormCalled = false

    override func constructWebview(assetSource: String? = nil) {
        constructWebviewCalled = true
        super.constructWebview(assetSource: assetSource)
    }

    override func destroyWebView() {
        destroyWebviewCalled = true
        super.destroyWebView()
    }

    override func dismissForm() {
        dismissFormCalled = true
        super.dismissForm()
    }
}

final class KlaviyoWebViewControllerTests: XCTestCase {
    private var mockPresentationManager: IAFPresentationManager!
    private var mockWebViewController: KlaviyoWebViewController!

    @MainActor
    override func setUp() async throws {
        let url = URL(string: "https://www.google.com")!
        let viewModel = MockIAFWebViewModel(url: url)
        mockWebViewController = KlaviyoWebViewController(viewModel: viewModel)
        mockPresentationManager = IAFPresentationManager(viewController: mockWebViewController)
    }

    override func tearDown() async throws {
        mockPresentationManager = nil
        mockWebViewController = nil
    }

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

    @MainActor
    func testDismissFormOnlyHidesWebView() {
        // Given
        let mockManager = MockIAFPresentationManager(viewController: mockWebViewController)

        // When
        mockManager.dismissForm()

        // Then
        XCTAssertTrue(mockManager.dismissFormCalled, "dismissForm should be called")
        XCTAssertFalse(mockManager.destroyWebviewCalled, "destroyWebView should not be called")
    }
}
