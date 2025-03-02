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

    // MARK: - Properties

    weak var delegate: KlaviyoWebViewDelegate?

    let url: URL
    var loadScripts: Set<WKUserScript>? = Set<WKUserScript>()
    var messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    private let companyId: String?
    private let assetSource: String?

    private let (formWillAppearStream, formWillAppearContinuation) = AsyncStream.makeStream(of: Void.self)

    // MARK: - Scripts

    private var klaviyoJsWKScript: WKUserScript? {
        var apiURL = environment.cdnURL()
        apiURL.path = "/onsite/js/klaviyo.js"
        apiURL.queryItems = [
            URLQueryItem(name: "company_id", value: companyId),
            URLQueryItem(name: "env", value: "in-app")
        ]

        if let assetSource {
            let assetSourceQueryItem = URLQueryItem(name: "assetSource", value: assetSource)
            apiURL.queryItems?.append(assetSourceQueryItem)
        }

        let klaviyoJsScript = """
            var script = document.createElement('script');
            script.id = 'klaviyoJS';
            script.type = 'text/javascript';
            script.src = '\(apiURL)';
            document.head.appendChild(script)
        """

        return WKUserScript(source: klaviyoJsScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private var sdkNameWKScript: WKUserScript {
        let sdkName = environment.sdkName()
        let sdkNameScript = "document.head.setAttribute('data-sdk-name', '\(sdkName)');"
        return WKUserScript(source: sdkNameScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private var sdkVersionWKScript: WKUserScript {
        let sdkVersion = environment.sdkVersion()
        let sdkVersionScript = "document.head.setAttribute('data-sdk-version', '\(sdkVersion)');"
        return WKUserScript(source: sdkVersionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private var handshakeWKScript: WKUserScript {
        let handshakeStringified = IAFNativeBridgeEvent.handshake
        let handshakeScript = "document.head.setAttribute('data-native-bridge-handshake', '\(handshakeStringified)');"
        return WKUserScript(source: handshakeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: - Initializer

    init(url: URL, companyId: String, assetSource: String? = nil) {
        self.url = url
        self.companyId = companyId
        self.assetSource = assetSource
        initializeLoadScripts()
    }

    func initializeLoadScripts() {
        guard let klaviyoJsWKScript else { return }
        loadScripts?.insert(klaviyoJsWKScript)
        loadScripts?.insert(sdkNameWKScript)
        loadScripts?.insert(sdkVersionWKScript)
        loadScripts?.insert(handshakeWKScript)
    }

    // MARK: - Loading

    func preloadWebsite(timeout: UInt64) async throws {
        guard let delegate else { return }

        await delegate.preloadUrl()

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                defer {
                    formWillAppearContinuation.finish()
                    group.cancelAll()
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: timeout)
                    throw PreloadError.timeout
                }

                group.addTask { [weak self] in
                    guard let self else { return }

                    var iterator = self.formWillAppearStream.makeAsyncIterator()
                    await iterator.next()
                }

                try await group.next()
            }
        } catch let error as PreloadError {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Loading time exceeded specified timeout of \(Float(timeout / 1_000_000_000), format: .fixed(precision: 1)) seconds.")
            }
            throw error
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error preloading URL: \(error)")
            }
            throw error
        }
    }

    // MARK: - handle WKWebView events

    func handleNavigationEvent(_ event: WKNavigationEvent) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.debug("Received navigation event: \(event.rawValue)")
        }
    }

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
            formWillAppearContinuation.yield()
            formWillAppearContinuation.finish()
        case .formDisappeared:
            Task {
                await delegate?.dismiss()
            }
        case let .trackProfileEvent(data):
            if let jsonEventData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let metricName = jsonEventData["metric"] as? String {
                KlaviyoSDK().create(event: Event(name: .customEvent(metricName), properties: jsonEventData))
            }
        case let .trackAggregateEvent(data):
            KlaviyoInternal.create(aggregateEvent: data)
        case let .openDeepLink(url):
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        case let .abort(reason):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Aborting webview: \(reason)")
            }
            Task {
                await delegate?.dismiss()
            }
        case .handShook:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successful handshake with JS")
            }
        }
    }
}
