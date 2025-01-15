//
//  JSTestWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/18/24.
//

#if DEBUG
import Combine
import Foundation
import WebKit

class JSTestWebViewModel: KlaviyoWebViewModeling {
    let url: URL
    let loadScripts: [String: WKUserScript]?
    weak var delegate: KlaviyoWebViewDelegate?

    /// Publishes scripts for the `WKWebView` to execute.
    private var continuation: AsyncStream<(script: String, callback: ((Result<Any?, Error>) -> Void)?)>.Continuation?
    lazy var scriptStream: AsyncStream<(script: String, callback: ((Result<Any?, Error>) -> Void)?)> = AsyncStream { [weak self] continuation in
        self?.continuation = continuation
    }

    init(url: URL) {
        self.url = url
        loadScripts = JSTestWebViewModel.initializeLoadScripts()
    }

    private static func initializeLoadScripts() -> [String: WKUserScript] {
        var scripts: [String: WKUserScript] = [:]

        if let toggleHandlerScript = try? FileIO.getFileContents(path: "toggleHandler", type: "js") {
            let script = WKUserScript(source: toggleHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            scripts["toggleMessageHandler"] = script
        }

        return scripts
    }

    // MARK: handle WKWebView events

    func handleNavigationEvent(_ event: WKNavigationEvent) {
        // TODO: handle navigation events
    }

    func handleScriptMessage(_ message: WKScriptMessage) {
        if message.name == "toggleMessageHandler" {
            guard let dict = message.body as? [String: AnyObject] else {
                return
            }

            guard let toggleEnabled = dict["toggleEnabled"] as? Bool else {
                return
            }

            print("toggle enabled: \(toggleEnabled)")

            let newStatus = toggleEnabled ? "Toggle is on" : "Toggle is off"

            let script = "document.getElementById('toggle-status').innerText = \"\(newStatus)\""

            // TODO: evaluate script in WebView
        }
    }
}
#endif
