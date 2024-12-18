//
//  KlaviyoWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

import Combine
import Foundation
import WebKit

class KlaviyoWebViewModel: KlaviyoWebViewModeling {
    let url: URL
    let loadScripts: [String: WKUserScript]?

    /// Publishes scripts for the `WKWebView` to execute.
    private var continuation: AsyncStream < (script: String, callback: (@Sendable (Result<Any?, Error>) -> Void)?)>.Continuation?
    lazy var scriptStream: AsyncStream < (script: String, callback: (@Sendable (Result<Any?, Error>) -> Void)?)> = AsyncStream { [weak self] continuation in
        self?.continuation = continuation
    }

    init(url: URL) {
        self.url = url
        loadScripts = KlaviyoWebViewModel.initializeLoadScripts()
    }

    private static func initializeLoadScripts() -> [String: WKUserScript] {
        var scripts: [String: WKUserScript] = [:]

        if let closeHandlerScript = try? FileIO.getFileContents(path: "closeHandler", type: "js") {
            #if swift(<6.0)
            let script = try WKUserScript(source: closeHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            scripts["closeHandler"] = script

            #else
            Task {
                let script = await WKUserScript(source: closeHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
                scripts["closeHandler"] = script
            }
            #endif
        }

        return scripts
    }

    // MARK: handle WKWebView events

    func handleNavigationEvent(_ event: WKNavigationEvent) {
        // TODO: handle navigation events
    }

    @MainActor
    func handleScriptMessage(_ message: WKScriptMessage) {
        if message.name == "closeHandler" {
            // TODO: handle close button tap
            print("user tapped close button")
        }
    }
}
