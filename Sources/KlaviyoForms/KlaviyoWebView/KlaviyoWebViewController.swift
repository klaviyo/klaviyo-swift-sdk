//
//  KlaviyoWebViewController.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/28/24.
//

import Combine
import OSLog
import UIKit
import WebKit

private var webConsoleLoggingEnabled: Bool {
    ProcessInfo.processInfo.environment["WEB_CONSOLE_LOGGING"] == "1"
}

private func createDefaultWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    // Required to allow localStorage data to be retained between webview instances
    config.websiteDataStore = WKWebsiteDataStore.default()

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.isOpaque = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never

    #if DEBUG
    if #available(iOS 16.4, *) {
        // Earlier versions do not require setting any kind of flag
        webView.isInspectable = true
    }
    #endif
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

        viewModel.messageHandlers?.forEach {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: $0)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        dismiss()
    }

    @MainActor
    private func loadUrl() {
        configureLoadScripts()
        let request = URLRequest(url: viewModel.url)
        webView.load(request)
    }

    @MainActor
    func preloadUrl() {
        loadUrl()
    }

    @MainActor
    func dismiss() {
        viewModel.messageHandlers?.forEach {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: $0)
        }
        #if DEBUG
        if webConsoleLoggingEnabled {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "consoleMessageHandler")
        }
        #endif
        dismiss(animated: false)
    }

    // MARK: - Scripts

    /// Configures the scripts to be injected into the website when the website loads.
    private func configureLoadScripts() {
        viewModel.loadScripts?.forEach {
            webView.configuration.userContentController.addUserScript($0)
        }

        viewModel.messageHandlers?.forEach {
            webView.configuration.userContentController.add(self, name: $0)
        }

        #if DEBUG
        if webConsoleLoggingEnabled {
            injectConsoleLoggingScript()
        }
        #endif
    }

    #if DEBUG
    private func injectConsoleLoggingScript() {
        guard let consoleHandlerScript = try? ResourceLoader.getResourceContents(path: "consoleHandler", type: "js") else {
            return
        }

        // Injects script at start of document, before any other scripts would load
        let strHandoff = "{\"bridgeName\":\"consoleMessageHandler\", \"linkConsole\":true}" // arguments to invoke with the JS bridge

        let script = WKUserScript(
            // Format as an immediately invoked function expression
            source: ";(\(consoleHandlerScript))('\(strHandoff)');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false)

        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.add(self, name: "consoleMessageHandler")
    }
    #endif

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

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url,
           await UIApplication.shared.open(url) {
            return .cancel
        } else {
            return .allow
        }
    }
}

// MARK: - Message Handling

extension KlaviyoWebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        #if DEBUG
        if message.name == "consoleMessageHandler" {
            if #available(iOS 14.0, *) {
                guard let jsonString = message.body as? String else { return }

                do {
                    let jsonData = Data(jsonString.utf8) // Convert string to Data
                    let consoleMessage = try JSONDecoder().decode(WebViewConsoleRelayMessage.self, from: jsonData)
                    handleJsConsoleMessage(consoleMessage)
                } catch {
                    Logger.webViewConsoleLogger.warning("Unable to decode WKWebView console relay message: \(error)")
                }
            }
        } else {
            viewModel.handleScriptMessage(message)
        }
        #else
        viewModel.handleScriptMessage(message)
        #endif
    }

    #if DEBUG
    @available(iOS 14.0, *)
    private func handleJsConsoleMessage(_ consoleMessage: WebViewConsoleRelayMessage) {
        switch consoleMessage.level {
        case .log:
            Logger.webViewConsoleLogger.log("\(consoleMessage.message)")
        case .warn:
            Logger.webViewConsoleLogger.warning("\(consoleMessage.message)")
        case .error:
            Logger.webViewConsoleLogger.error("\(consoleMessage.message)")
        }
    }
    #endif
}

// MARK: - Previews

#if DEBUG

@testable import KlaviyoSwift

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

#if swift(>=5.9)
@available(iOS 17.0, *)
#Preview("Klaviyo Form") {
    let companyId: String = "9BX3wh" // ⬅️ use a company ID that has a live form
    _ = klaviyoSwiftEnvironment.send(.initialize(companyId))
    let indexHtmlFileUrl = try! ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
    let viewModel = IAFWebViewModel(url: indexHtmlFileUrl, companyId: companyId)
    return createKlaviyoWebPreview(viewModel: viewModel)
}

@available(iOS 17.0, *)
#Preview("JS Test Page") {
    let indexHtmlFileUrl = try! ResourceLoader.getResourceUrl(path: "jstest", type: "html")
    let viewModel = PreviewWebViewModel(url: indexHtmlFileUrl)
    return KlaviyoWebViewController(viewModel: viewModel)
}
#endif
#endif
