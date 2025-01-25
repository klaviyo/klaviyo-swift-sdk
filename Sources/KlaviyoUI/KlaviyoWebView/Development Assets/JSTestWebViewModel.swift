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
    private enum MessageHandler: String, CaseIterable {
        case toggleMessageHandler
        case closeMessageHandler
    }

    weak var delegate: KlaviyoWebViewDelegate?

    let url: URL
    var loadScripts: Set<WKUserScript>? = JSTestWebViewModel.initializeLoadScripts()
    var messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    public let (navEventStream, navEventContinuation) = AsyncStream.makeStream(of: WKNavigationEvent.self)

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

    // MARK: handle WKWebView events

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
                await delegate?.dismiss()
            }
        }
    }
}
#endif
