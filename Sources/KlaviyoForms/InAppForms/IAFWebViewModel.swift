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
    let messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    let profileData: ProfileData
    private let assetSource: String?

    private var profileUpdatesCancellable: AnyCancellable?
    let formLifecycleStream: AsyncStream<IAFLifecycleEvent>
    private let formLifecycleContinuation: AsyncStream<IAFLifecycleEvent>.Continuation
    private let (handshakeStream, handshakeContinuation) = AsyncStream.makeStream(of: Void.self)

    // MARK: - Scripts

    @MainActor
    private var klaviyoJsWKScript: WKUserScript? {
        var apiURL = environment.cdnURL()
        apiURL.path = "/onsite/js/klaviyo.js"
        apiURL.queryItems = [
            URLQueryItem(name: "company_id", value: profileData.apiKey ?? ""),
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

    @MainActor
    private var sdkNameWKScript: WKUserScript {
        let sdkName = environment.sdkName()
        let sdkNameScript = "document.head.setAttribute('data-sdk-name', '\(sdkName)');"
        return WKUserScript(source: sdkNameScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    @MainActor
    private var sdkVersionWKScript: WKUserScript {
        let sdkVersion = environment.sdkVersion()
        let sdkVersionScript = "document.head.setAttribute('data-sdk-version', '\(sdkVersion)');"
        return WKUserScript(source: sdkVersionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    @MainActor
    private var dataEnvironmentWKScript: WKUserScript? {
        guard let formsEnv = environment.formsDataEnvironment()?.rawValue else { return nil }
        let sdkVersionScript = "document.head.setAttribute('data-forms-data-environment', '\(formsEnv)');"
        return WKUserScript(source: sdkVersionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    @MainActor
    private var handshakeWKScript: WKUserScript {
        let handshakeStringified = IAFNativeBridgeEvent.handshake
        let handshakeScript = "document.head.setAttribute('data-native-bridge-handshake', '\(handshakeStringified)');"
        return WKUserScript(source: handshakeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    @MainActor
    private var profileAttributesWKScript: WKUserScript? {
        guard let profileAttributesScript = createProfileAttributesScript(from: profileData) else { return nil }
        return WKUserScript(source: profileAttributesScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: - Initializer

    @MainActor
    init(url: URL, profileData: ProfileData, assetSource: String? = nil) {
        self.url = url
        self.profileData = profileData
        self.assetSource = assetSource

        let (stream, continuation) = AsyncStream.makeStream(of: IAFLifecycleEvent.self)
        formLifecycleStream = stream
        formLifecycleContinuation = continuation

        initializeLoadScripts()
        subscribeToProfileUpdates()
    }

    @MainActor
    func initializeLoadScripts() {
        guard let klaviyoJsWKScript else { return }
        loadScripts?.insert(klaviyoJsWKScript)
        loadScripts?.insert(sdkNameWKScript)
        loadScripts?.insert(sdkVersionWKScript)
        loadScripts?.insert(handshakeWKScript)
        if let profileAttributesWKScript {
            loadScripts?.insert(profileAttributesWKScript)
        }
        if let dataEnvironmentWKScript {
            loadScripts?.insert(dataEnvironmentWKScript)
        }
    }

    // MARK: - Loading

    func establishHandshake(timeout: TimeInterval) async throws {
        guard let delegate else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Required reference to `KlaviyoWebViewDelegate` is `nil`; unable to establish handshake")
            }
            throw ObjectStateError.objectDeallocated
        }

        await delegate.preloadUrl()

        do {
            try await withTimeout(seconds: timeout) { [weak self] in
                guard let self else { throw ObjectStateError.objectDeallocated }
                await self.handshakeStream.first { _ in true }
            }
        } catch let error as TimeoutError {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Handshake loading time exceeded specified timeout of \(timeout, format: .fixed(precision: 1)) seconds.")
            }
            throw error
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error establishing handshake: \(error)")
            }
            throw error
        }
    }

    // MARK: - Handle profile changes

    private func subscribeToProfileUpdates() {
        profileUpdatesCancellable = KlaviyoInternal.profileChangePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                guard case let .success(newProfileData) = result else { return }

                // if the profile update includes an API key change, this will be
                // handled by the IAFPresentationManager, not the IAFWebViewModel
                guard newProfileData.apiKey == self.profileData.apiKey else { return }

                if newProfileData != self.profileData {
                    self.handleProfileDataChange(newProfileData)
                }
            }
    }

    private func createProfileAttributesScript(from profileData: ProfileData) -> String? {
        guard let profileDataString = try? profileData.toHtmlString() else { return nil }
        let profileAttributesScript = "document.head.setAttribute('data-klaviyo-profile', '\(profileDataString)');"
        return profileAttributesScript
    }

    private func handleProfileDataChange(_ newProfileData: ProfileData) {
        guard let profileAttributesScript = createProfileAttributesScript(from: newProfileData) else { return }

        Task {
            do {
                let result = try await delegate?.evaluateJavaScript(profileAttributesScript)
                if let successMessage = result as? String {
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.info("Successfully evaluated Javascript; message: \(successMessage)")
                    }
                }
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Error evaluating Javascript; error: \(error)")
                }
            }
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
            ()
        case .formWillAppear:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received `formWillAppear` event from KlaviyoJS")
            }
            formLifecycleContinuation.yield(.present)
        case .formDisappeared:
            formLifecycleContinuation.yield(.dismiss)
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
            formLifecycleContinuation.yield(.abort)
        case .handShook:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successful handshake with JS")
            }
            handshakeContinuation.yield()
            handshakeContinuation.finish()
        case .analyticsEvent:
            ()
        case .lifecycleEvent:
            ()
        case .profileMutation:
            ()
        }
    }
}
