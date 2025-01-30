//
//  KlaviyoWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

import Combine
import Foundation
import KlaviyoSwift
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
    private enum MessageHandler: String, CaseIterable {
        case closeHandler
    }

    public weak var delegate: KlaviyoWebViewDelegate?

    public let url: URL
    public let loadScripts: Set<WKUserScript>? = KlaviyoWebViewModel.initializeLoadScripts()
    public var messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    public let (navEventStream, navEventContinuation) = AsyncStream.makeStream(of: WKNavigationEvent.self)

    public init(url: URL) {
        self.url = url
//        loadScripts = KlaviyoWebViewModel.initializeLoadScripts()
    }

    private static func initializeLoadScripts() -> Set<WKUserScript> {
        var scripts = Set<WKUserScript>()

        if let closeHandlerScript = try? ResourceLoader.getResourceContents(path: "closeHandler", type: "js") {
            let script = WKUserScript(source: closeHandlerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            scripts.insert(script)
        }

        return scripts
    }

    // MARK: handle WKWebView events

    // get formDidClose to call this and send the json payload
    public func handleScriptMessage(_ message: WKScriptMessage) {
        guard let handler = MessageHandler(rawValue: message.name) else {
            // script message has no handler
            return
        }

        // read the message.body into dict and get switch case
        let properties = ["form_id": "7uSP7t", "form_version_id": 8] as [String: Any]
        let event: Event.IAFProfileEvent = .profileEventTracked

        switch event {
        case .profileEventTracked:
            KlaviyoSDK().create(event: Event(name: .customEvent("Form completed by profile"), formProperties: properties))
        }

        switch handler {
        case .closeHandler:
            Task {
                await delegate?.dismiss()
            }
        }
    }
}
