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

    let apiKey: String
    let profileData: ProfileData?
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
            URLQueryItem(name: "company_id", value: apiKey),
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
        guard let profileData else { return nil }
        guard let profileAttributesScript = createProfileAttributesScript(from: profileData) else { return nil }
        return WKUserScript(source: profileAttributesScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: - Initializer

    @MainActor
    init(url: URL, apiKey: String, profileData: ProfileData?, assetSource: String? = nil) {
        self.url = url
        self.apiKey = apiKey
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

    @MainActor
    func establishHandshake(timeout: TimeInterval) async throws {
        guard let delegate else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Required reference to `KlaviyoWebViewDelegate` is `nil`; unable to establish handshake")
            }
            throw ObjectStateError.objectDeallocated
        }

        delegate.preloadUrl()

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

    @MainActor
    private func subscribeToProfileUpdates() {
        profileUpdatesCancellable = KlaviyoInternal.profileChangePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                guard case let .success(newProfileData) = result else { return }

                if newProfileData != self.profileData {
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.info("Profile data updated; new profile data:\n\(newProfileData.debugDescription)")
                    }
                    self.handleProfileDataChange(newProfileData)
                }
            }
    }

    @MainActor
    private func createProfileAttributesScript(from profileData: ProfileData) -> String? {
        guard let profileDataString = try? profileData.toHtmlString() else { return nil }
        let profileAttributesScript = "document.head.setAttribute('data-klaviyo-profile', '\(profileDataString)');"
        return profileAttributesScript
    }

    @MainActor
    private func handleProfileDataChange(_ newProfileData: ProfileData) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Attempting to update In-App Forms HTML with updated profile data")
        }
        guard let profileAttributesScript = createProfileAttributesScript(from: newProfileData) else { return }

        Task { @MainActor in
            do {
                let result = try await delegate?.evaluateJavaScript(profileAttributesScript)
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("Successfully updated In-App Forms HTML with updated profile data; message: \(result.debugDescription)")
                }
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Error updating In-App Forms HTML; error: \(error)")
                }
            }
        }
    }

    // MARK: - handle WKWebView events

    @MainActor
    func handleNavigationEvent(_ event: WKNavigationEvent) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.debug("Received navigation event: \(event.rawValue)")
        }
    }

    @MainActor
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

    @MainActor
    private func handleNativeBridgeEvent(_ event: IAFNativeBridgeEvent) {
        switch event {
        case .formsDataLoaded:
            ()
        case .formWillAppear:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'formWillAppear' event from KlaviyoJS")
            }
            formLifecycleContinuation.yield(.present)
        case .formDisappeared:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'formDisappeared' event from KlaviyoJS")
            }
            formLifecycleContinuation.yield(.dismiss)
        case let .trackProfileEvent(data):
            if let jsonEventData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let metricName = jsonEventData["metric"] as? String {
                KlaviyoSDK().create(event: Event(name: .customEvent(metricName), properties: jsonEventData))
            }
        case let .trackAggregateEvent(data):
            KlaviyoInternal.create(aggregateEvent: data)
        case let .openDeepLink(url):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'openDeepLink' event from KlaviyoJS with url: \(url, privacy: .public)")
            }
            if UIApplication.shared.canOpenURL(url) {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("Attempting to open URL '\(url, privacy: .public)'")
                }
                KlaviyoInternal.handleDeepLink(url: url)
            } else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Unable to open the URL '\(url, privacy: .public)'. This may be because a) the device does not have an installed app registered to handle the URL’s scheme, or b) you haven’t declared the URL’s scheme in your Info.plist file")
                }
            }
        case let .abort(reason):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'abort' event from KlaviyoJS with reason: \(reason, privacy: .public)")
            }
            formLifecycleContinuation.yield(.abort)
        case .handShook:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successful handshake with JS")
            }
            handshakeContinuation.yield()
            handshakeContinuation.finish()
            formLifecycleContinuation.yield(.handShook)
        case .analyticsEvent:
            ()
        case .lifecycleEvent:
            ()
        case .profileEvent:
            ()
        case .profileMutation:
            ()
        }
    }
}
