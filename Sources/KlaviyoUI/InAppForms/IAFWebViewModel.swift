//
//  IAFWebViewModel.swift
//  TestApp
//
//  Created by Andrew Balmer on 1/27/25.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog
import WebKit

class IAFWebViewModel: KlaviyoWebViewModeling {
    private enum MessageHandler: String, CaseIterable {
        case klaviyoNativeBridge = "KlaviyoNativeBridge"
    }

    weak var delegate: KlaviyoWebViewDelegate?

    let url: URL
    var loadScripts: Set<WKUserScript>? = Set<WKUserScript>()
    var messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    public let (navEventStream, navEventContinuation) = AsyncStream.makeStream(of: WKNavigationEvent.self)
    private var formWillAppearContinuation: CheckedContinuation<Void, Never>?

    init(url: URL) {
        self.url = url
        initializeLoadScripts()
    }

    func initializeLoadScripts() {
        let sdkName = environment.sdkName()
        let sdkNameScript = "document.head.setAttribute('data-sdk-name', '\(sdkName)');"
        let sdkNameWKScript = WKUserScript(source: sdkNameScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        loadScripts?.insert(sdkNameWKScript)

        let sdkVersion = environment.sdkVersion()
        let sdkVersionScript = "document.head.setAttribute('data-sdk-version', '\(sdkVersion)');"
        let sdkVersionWKScript = WKUserScript(source: sdkVersionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        loadScripts?.insert(sdkVersionWKScript)
    }

    func preloadWebsite(timeout: UInt64) async throws {
        guard let delegate else { return }

        await delegate.preloadUrl()

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: timeout)
                    throw PreloadError.timeout
                }

                group.addTask { [weak self] in
                    await withCheckedContinuation { continuation in
                        self?.formWillAppearContinuation = continuation
                    }
                }

                if let _ = try await group.next() {
                    // when the navigation task returns, we want to
                    // cancel both the timeout task and the navigation task
                    group.cancelAll()
                }
            }
        } catch PreloadError.timeout {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Loading time exceeded specified timeout of \(Float(timeout / 1_000_000_000), format: .fixed(precision: 1)) seconds.")
            }
            throw PreloadError.timeout
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error preloading URL: \(error)")
            }
            throw error
        }
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
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Failed to decode JSON: \(error)")
                }
            }
        }
    }

    private func handleNativeBridgeEvent(_ event: IAFNativeBridgeEvent) {
        switch event {
        case .formsDataLoaded:
            // TODO: handle formsDataLoaded
            ()
        case .formWillAppear:
            formWillAppearContinuation?.resume()
            formWillAppearContinuation = nil
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
