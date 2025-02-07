//
//  IAFWebViewModel.swift
//  TestApp
//
//  Created by Andrew Balmer on 1/27/25.
//

import Combine
import Foundation
import KlaviyoSwift
import WebKit

class IAFWebViewModel: KlaviyoWebViewModeling {
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
                let messageBusEvent = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: jsonData)
                handleNativeBridgeEvent(messageBusEvent)
            } catch {
                print("Failed to decode JSON: \(error)")
            }
        }
    }

    private func handleNativeBridgeEvent(_ event: IAFNativeBridgeEvent) {
        switch event {
        case .formsDataLoaded:
            // TODO: handle formsDataLoaded
            ()
        case .formWillAppear:
            Task {
                await IAFPresentationManager.shared.presentIAF()
            }
        case let .trackAggregateEvent(data):
            KlaviyoInternal.create(aggregateEvent: data)
        case let .trackProfileEvent(data):
            if let jsonEventData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let metricName = jsonEventData["metric"] as? String {
                KlaviyoSDK().create(event: Event(name: .customEvent(metricName), properties: jsonEventData))
            }
        case let .openDeepLink(url):
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        case .formDisappeared:
            Task {
                await delegate?.dismiss()
            }
        }
    }
}
