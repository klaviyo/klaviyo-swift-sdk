//
//  KlaviyoWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

import Combine
import Foundation
import WebKit

@_spi(KlaviyoPrivate)
public protocol KlaviyoWebViewDelegate: AnyObject {
    @MainActor
    func preloadUrl()

    @MainActor
    func evaluateJavaScript(_ script: String) async throws -> Any

    @MainActor
    func dismiss()
}

@_spi(KlaviyoPrivate)
public class KlaviyoWebViewModel: KlaviyoWebViewModeling {
    public let url: URL
    public let loadScripts: [String: WKUserScript]?
    public weak var delegate: KlaviyoWebViewDelegate?

    public let (navEventStream, navEventContinuation) = AsyncStream.makeStream(of: WKNavigationEvent.self)

    public init(url: URL) {
        self.url = url
        loadScripts = KlaviyoWebViewModel.initializeLoadScripts()
    }

    private static func initializeLoadScripts() -> [String: WKUserScript] {
        var scripts: [String: WKUserScript] = [:]

        if let closeHandlerScript = try? ResourceLoader.getResourceContents(path: "closeHandler", type: "js") {
            let script = WKUserScript(source: closeHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            scripts["closeHandler"] = script
        }

        return scripts
    }

    // MARK: handle WKWebView events

    public func handleScriptMessage(_ message: WKScriptMessage) {
        if message.name == "closeHandler" {
            // TODO: handle close button tap
            print("user tapped close button")

            Task {
                await delegate?.dismiss()
            }
        }
    }
}
