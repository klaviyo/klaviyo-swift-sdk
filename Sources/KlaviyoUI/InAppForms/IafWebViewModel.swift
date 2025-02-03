//
//  IafWebViewModel.swift
//  TestApp
//
//  Created by Andrew Balmer on 1/27/25.
//

import Combine
import Foundation
import KlaviyoSwift
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
            guard let jsonString = message.body as? String else { return }

            do {
                let jsonData = Data(jsonString.utf8) // Convert string to Data
                let messageBusEvent = try JSONDecoder().decode(IAFMessageBusEvent.self, from: jsonData)
                handleMessageBusEvent(messageBusEvent)
            } catch {
                print("Failed to decode JSON: \(error)")
            }
        }
    }

    private func handleMessageBusEvent(_ event: IAFMessageBusEvent) {
        switch event {
        case .formsDataLoaded:
            // TODO: handle formsDataLoaded
            ()
        case .formAppeared:
            // TODO: handle formAppeared
            ()
        case let .trackAggregateEvent(data):
            KlaviyoSDK().create(aggregateEvent: data)
        case .trackProfileEvent:
            // TODO: handle tracktProfileEvent
            ()
        case .openDeepLink:
            // TODO: handle openDeepLink
            ()
        }
    }
}
