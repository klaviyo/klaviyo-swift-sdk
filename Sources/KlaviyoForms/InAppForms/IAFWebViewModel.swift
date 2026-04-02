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
    var htmlContent: String?
    var loadScripts: Set<WKUserScript>? = Set<WKUserScript>()
    let messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    let apiKey: String
    let profileData: ProfileData?
    private let assetSource: String?

    private var profileUpdatesCancellable: AnyCancellable?
    let formLifecycleStream: AsyncStream<IAFLifecycleEvent>
    private let formLifecycleContinuation: AsyncStream<IAFLifecycleEvent>.Continuation
    private let (handshakeStream, handshakeContinuation) = AsyncStream.makeStream(of: Void.self)

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

        buildHtmlContent()
        subscribeToProfileUpdates()
    }

    // MARK: - Template Building

    /// Builds the HTML content by reading the template and replacing placeholders with actual values.
    /// This ensures all data attributes (handshake, SDK info, etc.) are present in the initial HTML
    /// before KlaviyoJS loads, matching Android's template replacement approach.
    @MainActor
    private func buildHtmlContent() {
        guard let templateString = try? ResourceLoader.getResourceContents(
            path: "InAppFormsTemplate",
            type: "html"
        ) else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Failed to read InAppFormsTemplate.html; falling back to URL loading")
            }
            return
        }

        var apiURL = environment.cdnURL()
        apiURL.path = "/onsite/js/klaviyo.js"
        apiURL.queryItems = [
            URLQueryItem(name: "company_id", value: apiKey),
            URLQueryItem(name: "env", value: "in-app")
        ]

        if let assetSource {
            apiURL.queryItems?.append(URLQueryItem(name: "assetSource", value: assetSource))
        }

        let klaviyoJsScriptTag = "<script type=\"text/javascript\" src=\"\(apiURL)\"></script>"

        let profileDataString: String
        if let profileData, let encoded = try? profileData.toHtmlString() {
            profileDataString = encoded
        } else {
            profileDataString = "{}"
        }

        let formsEnv = environment.formsDataEnvironment()?.rawValue ?? ""

        htmlContent = templateString
            .replacingOccurrences(of: "SDK_NAME", with: environment.sdkName())
            .replacingOccurrences(of: "SDK_VERSION", with: environment.sdkVersion())
            .replacingOccurrences(of: "BRIDGE_HANDSHAKE", with: IAFNativeBridgeEvent.handshake)
            .replacingOccurrences(of: "FORMS_ENVIRONMENT", with: formsEnv)
            .replacingOccurrences(of: "PROFILE_DATA", with: profileDataString)
            .replacingOccurrences(of: "KLAVIYO_JS_SCRIPT", with: klaviyoJsScriptTag)
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
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Unknown message handler: \(message.name, privacy: .public)")
            }
            return
        }

        switch handler {
        case .klaviyoNativeBridge:
            guard let jsonString = message.body as? String else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Message body is not a string: \(type(of: message.body), privacy: .public)")
                }
                return
            }

            if #available(iOS 14.0, *) {
                Logger.webViewLogger.debug("Received native bridge message: \(jsonString.prettyPrintedJSON)")
            }

            do {
                let jsonData = Data(jsonString.utf8) // Convert string to Data
                let messageBusEvent = try JSONDecoder().decode(IAFNativeBridgeEvent.self, from: jsonData)
                handleNativeBridgeEvent(messageBusEvent)
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Failed to decode JSON: \(error)")
                    Logger.webViewLogger.warning("Raw JSON: \(jsonString.prettyPrintedJSON)")
                }
            }
        }
    }

    @MainActor
    private func handleNativeBridgeEvent(_ event: IAFNativeBridgeEvent) {
        switch event {
        case .formsDataLoaded:
            ()
        case let .formWillAppear(data):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'formWillAppear' event from KlaviyoJS")
            }

            do {
                let payload = try JSONDecoder().decode(FormWillAppearPayload.self, from: data)
                let layout = payload.layout ?? FormLayout(position: .fullscreen)
                formLifecycleContinuation.yield(.present(formId: payload.formId, formName: payload.formName, withLayout: layout))
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Failed to parse formWillAppear payload: \(error.localizedDescription)")
                }
                formLifecycleContinuation.yield(.present(formId: nil, formName: nil, withLayout: FormLayout(position: .fullscreen)))
            }
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
                Logger.webViewLogger.info("Received 'openDeepLink' event from KlaviyoJS with url: \(url?.absoluteString ?? "nil", privacy: .public)")
            }

            // Notify lifecycle handler that CTA was clicked (always fire, even if URL is nil/invalid)
            IAFPresentationManager.shared.invokeLifecycleHandler(for: .formCTAClicked)

            // Only attempt to open valid URLs (skip if nil or empty)
            guard let url = url, !url.absoluteString.isEmpty else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("CTA clicked but no deep link URL configured in form")
                }
                return
            }

            if UIApplication.shared.canOpenURL(url) {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("Attempting to open URL '\(url, privacy: .public)'")
                }
                KlaviyoInternal.handleDeepLink(url: url)
            } else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Unable to open the URL '\(url, privacy: .public)'. This may be because a) the device does not have an installed app registered to handle the URL's scheme, or b) you haven't declared the URL's scheme in your Info.plist file")
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

// MARK: - FormWillAppearPayload

private struct FormWillAppearPayload: Codable {
    let formId: String?
    let formName: String?
    let layout: FormLayout?
}
