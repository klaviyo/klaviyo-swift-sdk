//
//  IafWebViewModel.swift
//  TestApp
//
//  Created by Andrew Balmer on 1/27/25.
//

import Combine
import Foundation
import WebKit

class IafWebViewModel: KlaviyoWebViewModeling {
    private enum MessageHandler: String, CaseIterable {
        case klaviyoNativeBridge = "KlaviyoNativeBridge"
    }

    weak var delegate: KlaviyoWebViewDelegate?

    let url: URL
    var loadScripts: Set<WKUserScript>?
    var messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    public let (navEventStream, navEventContinuation) = AsyncStream.makeStream(of: WKNavigationEvent.self)

    init(url: URL) {
        self.url = url
    }

    // MARK: handle WKWebView events

    func handleScriptMessage(_ message: WKScriptMessage) {
        guard let handler = MessageHandler(rawValue: message.name) else {
            // script message has no handler
            return
        }

        switch handler {
        case .klaviyoNativeBridge:
            guard let jsonString = message.body as? String else {
                return
            }
            // TODO: handle bridge messages
        }
    }
}
