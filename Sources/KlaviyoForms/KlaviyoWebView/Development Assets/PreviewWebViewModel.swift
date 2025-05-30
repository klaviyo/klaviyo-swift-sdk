//
//  PreviewWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/18/24.
//

#if DEBUG
import Combine
import Foundation
import KlaviyoCore
import WebKit

// ViewModel for testing the KlaviyoWebViewController & KlaviyoWebViewModeling protocol in Xcode previews only.
class PreviewWebViewModel: KlaviyoWebViewModeling {
    private enum MessageHandler: String, CaseIterable {
        case toggleMessageHandler
        case closeMessageHandler
    }

    weak var delegate: KlaviyoWebViewDelegate?

    let url: URL
    var loadScripts: Set<WKUserScript>? = PreviewWebViewModel.initializeLoadScripts()
    var messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    private let (navEventStream, navEventContinuation) = AsyncStream.makeStream(of: WKNavigationEvent.self)

    init(url: URL) {
        self.url = url
    }

    private static func initializeLoadScripts() -> Set<WKUserScript> {
        var scripts = Set<WKUserScript>()

        if let toggleHandlerScript = try? ResourceLoader.getResourceContents(path: "toggleHandler", type: "js") {
            let script = WKUserScript(source: toggleHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            scripts.insert(script)
        }

        if let closeHandlerScript = try? ResourceLoader.getResourceContents(path: "closeHandler", type: "js") {
            let script = WKUserScript(source: closeHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            scripts.insert(script)
        }

        return scripts
    }

    /// Tells the delegate's ``WKWebView`` to preload the URL provided in this ViewModel.
    ///
    /// This async method will return after the preload has completed.
    ///
    /// By preloading, we can load the URL "headless", so that the ViewController containing
    /// the ``WKWebView`` will only be presented after the site has successfully loaded.
    ///
    /// The caller of this method should `await` completion of this method, then present the ViewController.
    /// - Parameter timeout: the amount of time, in milliseconds, to wait before throwing a `timeout` error.
    public func preloadWebsite(timeout: TimeInterval) async throws {
        guard let delegate else { return }

        await delegate.preloadUrl()

        do {
            try await withTimeout(seconds: timeout) { [weak self] in
                guard let self else { return }
                for await event in self.navEventStream {
                    switch event {
                    case .didFinishNavigation:
                        return
                    case .didFailNavigation,
                         .didCommitNavigation,
                         .didStartProvisionalNavigation,
                         .didFailProvisionalNavigation,
                         .didReceiveServerRedirectForProvisionalNavigation:
                        continue
                    }
                }
            }
        } catch let error as TimeoutError {
            switch error {
            case .timeout:
                print("Operation timed out: \(error)")
                throw error
            }
        } catch {
            print("Operation encountered an error: \(error)")
            throw error
        }
    }

    // MARK: handle WKWebView events

    public func handleNavigationEvent(_ event: WKNavigationEvent) {
        navEventContinuation.yield(event)
    }

    func handleScriptMessage(_ message: WKScriptMessage) {
        guard let handler = MessageHandler(rawValue: message.name) else {
            // script message has no handler
            return
        }

        switch handler {
        case .toggleMessageHandler:
            guard let dict = message.body as? [String: AnyObject] else {
                return
            }

            guard let toggleEnabled = dict["toggleEnabled"] as? Bool else {
                return
            }

            print("toggle enabled: \(toggleEnabled)")

            let newStatus = toggleEnabled ? "Toggle is on" : "Toggle is off"

            let script = "document.getElementById('toggle-status').innerText = \"\(newStatus)\""

            Task {
                do {
                    let result = try await delegate?.evaluateJavaScript(script)
                    if let successMessage = result as? String {
                        print("Successfully evaluated Javascript; message: \(successMessage)")
                    }
                } catch {
                    print("Javascript evaluation failed; message: \(error.localizedDescription)")
                }
            }
        case .closeMessageHandler:
            Task {
                await delegate?.dismiss(animated: false)
            }
        }
    }
}
#endif
