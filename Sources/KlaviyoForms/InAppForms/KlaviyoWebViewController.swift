//
//  KlaviyoWebViewController.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/28/24.
//

import Combine
import KlaviyoSwift
import OSLog
import UIKit
import WebKit

enum MessageHandler: String, CaseIterable {
    case klaviyoNativeBridge = "KlaviyoNativeBridge"
}

private var webConsoleLoggingEnabled: Bool {
    ProcessInfo.processInfo.environment["WEB_CONSOLE_LOGGING"] == "1"
}

class KlaviyoWebViewController: UIViewController {
    private var webView: WKWebView? = {
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
    }()

    private weak var viewModel: IAFWebViewModel?

    // MARK: - Initializers

    init(viewModel: IAFWebViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        webView?.navigationDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View loading

    override func loadView() {
        view = UIView()
        if let webView = webView {
            view.addSubview(webView)
        }

        configureSubviewConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard (webView?.isLoading) == nil,
              webView?.estimatedProgress != 1.0 else { return }

        loadUrl()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        guard let viewModel = viewModel else {
            return
        }

        viewModel.messageHandlers?.forEach {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: $0)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        dismiss()
    }

    @MainActor
    private func loadUrl() {
        configureLoadScripts()
        guard let viewModel = viewModel else {
            return
        }
        let request = URLRequest(url: viewModel.url)
        webView?.load(request)
    }

    func preloadWebsite(timeout: UInt64) async throws {
        await preloadUrl()

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                defer {
                    viewModel?.formWillAppearContinuation.finish()
                    group.cancelAll()
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: timeout)
                    throw PreloadError.timeout
                }

                group.addTask { [weak self] in
                    guard let self else { return }

                    var iterator = viewModel?.formWillAppearStream.makeAsyncIterator()
                    await iterator?.next()
                }

                try await group.next()
            }
        } catch let error as PreloadError {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Loading time exceeded specified timeout of \(Float(timeout / 1_000_000_000), format: .fixed(precision: 1)) seconds.")
            }
            throw error
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error preloading URL: \(error)")
            }
            throw error
        }
    }

    @MainActor
    func preloadUrl() {
        loadUrl()
    }

    @MainActor
    func dismiss() {
        #if DEBUG
        if webConsoleLoggingEnabled {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "consoleMessageHandler")
        }
        #endif
        dismiss(animated: true)
    }

    // MARK: - Scripts

    /// Configures the scripts to be injected into the website when the website loads.
    private func configureLoadScripts() {
        guard let viewModel = viewModel else {
            return
        }

        viewModel.loadScripts?.forEach {
            webView?.configuration.userContentController.addUserScript($0)
        }

        viewModel.messageHandlers?.forEach {
            webView?.configuration.userContentController.add(self, name: $0)
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

        webView?.configuration.userContentController.addUserScript(script)
        webView?.configuration.userContentController.add(self, name: "consoleMessageHandler")
    }
    #endif

    // MARK: - Layout

    private func configureSubviewConstraints() {
        webView?.translatesAutoresizingMaskIntoConstraints = false
        webView?.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webView?.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        webView?.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        webView?.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }
}

extension KlaviyoWebViewController: WKNavigationDelegate {
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
            handleScriptMessage(message)
        }
        #else
        handleScriptMessage(message)
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

    func handleScriptMessage(_ message: WKScriptMessage) {
        guard let handler = MessageHandler(rawValue: message.name) else {
            // script message has no handler
            return
        }

        switch handler {
        case .klaviyoNativeBridge:
            guard let jsonString = message.body as? String else { return }

            do {
                let jsonData = Data(jsonString.utf8) // Convert string to Data
                let messageBusEvent = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: jsonData)
                handleNativeBridgeEvent(messageBusEvent)
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Failed to decode JSON: \(error)")
                }
            }
        }
    }

    private func handleNativeBridgeEvent(_ event: IAFNativeBridgeEvent) {
        switch event {
        case .formWillAppear:
            viewModel?.formWillAppearContinuation.yield()
            viewModel?.formWillAppearContinuation.finish()
        case .formDisappeared:
            Task {
                await dismiss()
            }
        case let .trackProfileEvent(data):
            if let jsonEventData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let metricName = jsonEventData["metric"] as? String {
                KlaviyoSDK().create(event: Event(name: .customEvent(metricName), properties: jsonEventData))
            }
        case let .trackAggregateEvent(data):
            KlaviyoInternal.create(aggregateEvent: data)
        case let .openDeepLink(url):
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        case let .abort(reason):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Aborting webview: \(reason)")
            }
            Task {
                await dismiss()
            }
        case .handShook:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successful handshake with JS")
            }
        }
    }
}
