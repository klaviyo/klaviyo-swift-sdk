//
//  KlaviyoWebViewController.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/28/24.
//

import Combine
import UIKit
import WebKit

private func createDefaultWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.isOpaque = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    return webView
}

class KlaviyoWebViewController: UIViewController, WKUIDelegate, KlaviyoWebViewDelegate {
    private lazy var webView: WKWebView = {
        let webView = createWebView()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        return webView
    }()

    private var viewModel: KlaviyoWebViewModeling
    private let createWebView: () -> WKWebView

    // MARK: - Initializers

    init(viewModel: KlaviyoWebViewModeling, webViewFactory: @escaping () -> WKWebView = createDefaultWebView) {
        self.viewModel = viewModel
        createWebView = webViewFactory
        super.init(nibName: nil, bundle: nil)
        self.viewModel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View loading

    override func loadView() {
        view = UIView()
        view.addSubview(webView)

        configureLoadScripts()
        configureSubviewConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard !webView.isLoading,
              webView.estimatedProgress != 1.0 else { return }

        loadUrl()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        let scriptNames = viewModel.loadScripts?.keys.compactMap { $0 } ?? []
        for scriptName in scriptNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: scriptName)
        }
    }

    @MainActor
    private func loadUrl() {
        let request = URLRequest(url: viewModel.url)
        webView.load(request)
    }

    @MainActor
    func preloadUrl() {
        loadUrl()
    }

    // MARK: - Scripts

    /// Configures the scripts to be injected into the website when the website loads.
    private func configureLoadScripts() {
        guard let scriptsDict = viewModel.loadScripts else { return }

        for (name, script) in scriptsDict {
            webView.configuration.userContentController.addUserScript(script)
            webView.configuration.userContentController.add(self, name: name)
        }
    }

    @MainActor
    func evaluateJavaScript(_ script: String) async throws -> Any {
        try await webView.evaluateJavaScript(script)
    }

    // MARK: - Layout

    private func configureSubviewConstraints() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        webView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }
}

extension KlaviyoWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        viewModel.handleNavigationEvent(.didStartProvisionalNavigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        viewModel.handleNavigationEvent(.didFailProvisionalNavigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        viewModel.handleNavigationEvent(.didFinishNavigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        viewModel.handleNavigationEvent(.didFailNavigation)
    }
}

extension KlaviyoWebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        viewModel.handleScriptMessage(message)
    }
}

// MARK: - Previews

#if DEBUG
func createKlaviyoWebPreview(viewModel: KlaviyoWebViewModeling) -> UIViewController {
    let viewController = KlaviyoWebViewController(viewModel: viewModel)

    // Add a dummy view as a parent to the KlaviyoWebViewController to preview what the
    // KlaviyoWebViewController might look like when it's displayed on top of a view in an app.
    let parentViewController = PreviewTabViewController()

    parentViewController.addChild(viewController)
    parentViewController.view.addSubview(viewController.view)
    viewController.didMove(toParent: parentViewController)

    viewController.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        viewController.view.topAnchor.constraint(equalTo: parentViewController.view.topAnchor),
        viewController.view.bottomAnchor.constraint(equalTo: parentViewController.view.bottomAnchor),
        viewController.view.leadingAnchor.constraint(equalTo: parentViewController.view.leadingAnchor),
        viewController.view.trailingAnchor.constraint(equalTo: parentViewController.view.trailingAnchor)
    ])

    return parentViewController
}
#endif

#if swift(>=5.9)
@available(iOS 17.0, *)
#Preview("Klaviyo.com") {
    let url = URL(string: "https://picsum.photos/200/300")!
    let viewModel = KlaviyoWebViewModel(url: url)
    return createKlaviyoWebPreview(viewModel: viewModel)
}

@available(iOS 17.0, *)
#Preview("Klaviyo Form") {
    let indexHtmlFileUrl = Bundle.module.url(forResource: "klaviyo", withExtension: "html")!
    let viewModel = KlaviyoWebViewModel(url: indexHtmlFileUrl)
    return createKlaviyoWebPreview(viewModel: viewModel)
}

@available(iOS 17.0, *)
#Preview("JS Test Page") {
    let indexHtmlFileUrl = Bundle.module.url(forResource: "jstest", withExtension: "html")!
    let viewModel = JSTestWebViewModel(url: indexHtmlFileUrl)
    return KlaviyoWebViewController(viewModel: viewModel)
}
#endif
