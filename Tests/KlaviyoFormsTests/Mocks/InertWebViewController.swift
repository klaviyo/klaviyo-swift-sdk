//
//  InertWebViewController.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import WebKit

/// Never loads a page, so no WebKit content process is started.
final class InertWebView: WKWebView {
    override func load(_ request: URLRequest) -> WKNavigation? {
        nil
    }
}

/// Hosts an ``InertWebView`` and completes every script evaluation immediately.
final class InertWebViewController: KlaviyoWebViewController {
    convenience init(hosting viewModel: KlaviyoWebViewModeling) {
        self.init(viewModel: viewModel, webViewFactory: { InertWebView() })
    }

    override func evaluateJavaScript(_ script: String) async throws -> Any? {
        nil
    }
}
