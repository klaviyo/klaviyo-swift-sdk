//
//  KlaviyoWebViewController.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/28/24.
//

import Combine
import UIKit
import WebKit

class KlaviyoWebViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!
    private let viewModel: KlaviyoWebViewModeling

    // MARK: - Initializers

    init(viewModel: KlaviyoWebViewModeling) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View loading

    override func loadView() {
        super.loadView()

        let config = createWebViewConfiguration()
        webView = createWebView(with: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        view.addSubview(webView)

        configureLoadScripts()
        configureScriptEvaluator()
        configureSubviewConstraints()
    }

    override func viewDidLoad() {
        let request = URLRequest(url: viewModel.url)
        webView.load(request)
    }

    // MARK: - WKWebView configuration

    func createWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        // customize any WKWebViewConfiguration properties here
        // ex: config.allowsInlineMediaPlayback = true
        return config
    }

    func createWebView(with config: WKWebViewConfiguration) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: config)
        // customize any WKWebView behaviors here
        // ex: webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        return webView
    }

    // MARK: - Scripts

    /// Configures the scripts to be injected into the website when the website loads.
    func configureLoadScripts() {
        guard let scriptsDict = viewModel.loadScripts else { return }

        for (name, script) in scriptsDict {
            webView.configuration.userContentController.addUserScript(script)
            webView.configuration.userContentController.add(self, name: name)
        }
    }

    @MainActor
    func configureScriptEvaluator() {
        Task { [weak self] in
            guard let self else { return }

            for await (script, callback) in self.viewModel.scriptStream {
                do {
                    let result = try await self.webView.evaluateJavaScript(script)
                    callback?(.success(result))
                } catch {
                    callback?(.failure(error))
                }
            }
        }
    }

    // MARK: - Layout

    func configureSubviewConstraints() {
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
func createKlaviyoWebPreview(url: URL) -> UIViewController {
    let viewModel = KlaviyoWebViewModel(url: url)
    let viewController = KlaviyoWebViewController(viewModel: viewModel)

    // Add a dummy view as a parent to the KlaviyoWebViewController to preview what the
    // KlaviyoWebViewController might look like when it's displayed on top of a view in an app.
    let parentViewController = PreviewTabViewController()
    parentViewController.view.addSubview(viewController.view)

    return parentViewController
}
#endif

#if swift(>=5.9)
@available(iOS 17.0, *)
#Preview("Klaviyo.com") {
    let url = URL(string: "https://picsum.photos/200/300")!
    return createKlaviyoWebPreview(url: url)
}

@available(iOS 17.0, *)
#Preview("Klaviyo Form") {
    let indexHtmlFileUrl = Bundle.module.url(forResource: "klaviyo", withExtension: "html")!
    return createKlaviyoWebPreview(url: indexHtmlFileUrl)
}
#endif
