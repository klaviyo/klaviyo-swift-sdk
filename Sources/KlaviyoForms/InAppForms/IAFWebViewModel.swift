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

// swiftlint:disable:next type_body_length
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
    let authToken: String?
    private let assetSource: String?

    private var profileUpdatesCancellable: AnyCancellable?
    let formLifecycleStream: AsyncStream<IAFLifecycleEvent>
    private let formLifecycleContinuation: AsyncStream<IAFLifecycleEvent>.Continuation
    private let (handshakeStream, handshakeContinuation) = AsyncStream.makeStream(of: Void.self)

    /// Maximum number of fresh-token fetches attempted per WebView in response
    /// to `badJWT`, so a provider that always returns an invalid token can't
    /// retry forever.
    private static let maxBadJWTRetryAttempts = 2
    private var badJWTRetryAttempts = 0

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

    @MainActor
    private var authTokenWKScript: WKUserScript? {
        guard let authToken else { return nil }
        let authTokenScript = createAuthTokenScript(from: authToken)
        return WKUserScript(source: authTokenScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    /// Publishes a snapshot of the current `DeviceInfo` onto `document.head` before any
    /// inline `<script>` in the template runs. Injected at `.atDocumentStart` so that
    /// onsite can consult `document.head.dataset.klaviyoDevice` during the synchronous
    /// HTML parse phase — this is what distinguishes it from the other `.atDocumentEnd`
    /// attribute injections in this file.
    ///
    /// Note on staleness: this is a computed property re-evaluated each time
    /// `setupLoadScripts` assembles the script set, so each navigation captures a fresh
    /// snapshot. Any device-state change between `loadScripts` assembly and the document
    /// parse is corrected at runtime by `pushDeviceInfo()` via `evaluateJavaScript` on
    /// `viewWillTransition` / `viewSafeAreaInsetsDidChange`, so onsite's first runtime
    /// read sees the up-to-date value. IAF view models are 1:1 with a form presentation,
    /// so the parse-time staleness window is small and acceptable.
    @MainActor
    private var deviceInfoWKScript: WKUserScript {
        let script = DeviceInfo.current().asAttributeAssignmentScript()
        return WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    // MARK: - Initializer

    @MainActor
    init(
        url: URL,
        apiKey: String,
        profileData: ProfileData?,
        authToken: String? = nil,
        assetSource: String? = nil
    ) {
        self.url = url
        self.apiKey = apiKey
        self.profileData = profileData
        self.authToken = authToken
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
        loadScripts?.insert(deviceInfoWKScript)
        if let profileAttributesWKScript {
            loadScripts?.insert(profileAttributesWKScript)
        }
        if let authTokenWKScript {
            loadScripts?.insert(authTokenWKScript)
        }
        if let dataEnvironmentWKScript {
            loadScripts?.insert(dataEnvironmentWKScript)
        }
    }

    /// Push a fresh `DeviceInfo` snapshot to the webview's `data-klaviyo-device` head
    /// attribute. Called from the view controller on orientation and safe-area changes
    /// so onsite stays in sync with the device state.
    @MainActor
    func pushDeviceInfo() {
        let script = DeviceInfo.current().asAttributeAssignmentScript()
        Task { @MainActor in
            do {
                _ = try await delegate?.evaluateJavaScript(script)
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Error pushing updated device info to web view: \(error)")
                }
            }
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
        return "document.head.setAttribute('data-klaviyo-profile', '\(profileDataString)');"
    }

    @MainActor
    private func createAuthTokenScript(from token: String) -> String {
        "document.head.setAttribute('data-klaviyo-jwt', '\(token)');"
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

    // MARK: - Handle token refreshes

    /// Pushes a refreshed auth token into the live page, updating the
    /// `data-klaviyo-jwt` head attribute so onsite re-reads the new token without
    /// a reload. Driven by ``IAFPresentationManager``'s refresh subscription,
    /// which owns the `AuthTokenManager.refreshes()` stream for the WebView's
    /// lifetime; this method is the per-token push, mirroring ``pushDeviceInfo()``.
    ///
    /// `async` so the caller can await it and apply refreshes in arrival order.
    /// The token value is never logged — only the success/failure of the update.
    @MainActor
    func pushAuthToken(_ token: String) async {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Auth token refreshed; updating In-App Forms HTML")
        }
        let authTokenScript = createAuthTokenScript(from: token)
        do {
            _ = try await delegate?.evaluateJavaScript(authTokenScript)
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successfully updated In-App Forms HTML with refreshed auth token")
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error updating In-App Forms HTML with refreshed auth token; error: \(error)")
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
        case let .formWillAppear(formId, formName, layout):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'formWillAppear' event from KlaviyoJS")
            }
            formLifecycleContinuation.yield(.present(withLayout: layout ?? FormLayout(position: .fullscreen)))
            if let formId, !formId.isEmpty,
               let formName, !formName.isEmpty {
                IAFPresentationManager.shared.invokeLifecycleHandler(
                    for: .formShown(formId: formId, formName: formName)
                )
            } else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning(
                        "formWillAppear missing metadata — skipping lifecycle callback"
                    )
                }
            }
        case let .formDisappeared(formId, formName):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'formDisappeared' event from KlaviyoJS")
            }
            formLifecycleContinuation.yield(.dismiss)
            if let formId, !formId.isEmpty,
               let formName, !formName.isEmpty {
                IAFPresentationManager.shared.invokeLifecycleHandler(
                    for: .formDismissed(formId: formId, formName: formName)
                )
            } else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning(
                        "formDisappeared missing metadata — skipping lifecycle callback"
                    )
                }
            }
        case let .trackProfileEvent(data):
            if let jsonEventData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let metricName = jsonEventData["metric"] as? String {
                KlaviyoSDK().create(event: Event(name: .customEvent(metricName), properties: jsonEventData))
            }
        case let .trackAggregateEvent(data):
            KlaviyoInternal.create(aggregateEvent: data)
        case let .openDeepLink(url, formId, formName, buttonLabel):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'openDeepLink' event from KlaviyoJS with url: \(url?.absoluteString ?? "nil", privacy: .public)")
            }

            // 1. Check URL exists and is non-empty — no URL means no navigation and no lifecycle event
            guard let url = url, !url.absoluteString.isEmpty else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning(
                        "CTA clicked but no deep link URL configured — skipping navigation"
                    )
                }
                return
            }

            // 2. Handle deep link navigation before validating lifecycle metadata
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

            // 3. Invoke lifecycle handler when form identity fields are present
            //    buttonLabel is allowed to be nil/empty — a CTA with no text is still a valid click
            if let formId, !formId.isEmpty,
               let formName, !formName.isEmpty {
                IAFPresentationManager.shared.invokeLifecycleHandler(for: .formCtaClicked(
                    formId: formId,
                    formName: formName,
                    buttonLabel: buttonLabel ?? "",
                    deepLinkUrl: url
                ))
            } else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning(
                        "openDeepLink missing metadata — skipping lifecycle callback"
                    )
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
        case .jwtMutation:
            ()
        case .badJWT:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("KlaviyoJS rejected the injected auth token (BadJWT)")
            }
            handleBadJWT()
        }
    }

    /// Maximum number of internal fetch attempts ``fetchAndPushFreshToken(attempt:)``
    /// makes per `badJWT` rejection before giving up. Separate from
    /// ``maxBadJWTRetryAttempts``: that bounds how many *incoming* `badJWT`
    /// messages trigger a recovery attempt at all; this bounds how hard a
    /// single attempt tries before accepting defeat.
    private static let maxInternalFetchAttempts = 3

    /// Responds to a `badJWT` rejection by fetching a genuinely fresh token and
    /// pushing it, resolving KlaviyoJS's pending `awaitNextSetJWT()`.
    ///
    /// The rejected token must be invalidated before re-fetching — the cache
    /// would otherwise hand back the same bad token, since a `badJWT`
    /// rejection isn't reflected in the token's own `exp` claim. Bounded by
    /// ``maxBadJWTRetryAttempts`` since a provider that always returns an
    /// invalid token would otherwise retry indefinitely.
    @MainActor
    private func handleBadJWT() {
        guard badJWTRetryAttempts < Self.maxBadJWTRetryAttempts else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("BadJWT retry limit reached; no further attempts will be made")
            }
            return
        }
        badJWTRetryAttempts += 1

        Task { @MainActor in
            await AuthTokenManager.shared.clearTokenState()
            await fetchAndPushFreshToken(attempt: 1)
        }
    }

    /// Fetches a fresh token and pushes it, retrying internally on failure.
    ///
    /// `clearTokenState()` (called once by ``handleBadJWT()`` before this
    /// runs) drops the proactive-refresh schedule as a side effect of
    /// invalidating the rejected token — nothing re-arms it until a fetch
    /// here succeeds. Without an internal retry, a single transient failure
    /// (timeout, network blip) would leave this WebView with no scheduled
    /// refresh and no cached token: no further recovery for the rest of its
    /// lifetime, since ``handleBadJWT()`` only reacts to *new* `badJWT`
    /// messages and fender may not send another. Retrying here — rather than
    /// waiting on another `badJWT` — is what actually closes that gap.
    @MainActor
    private func fetchAndPushFreshToken(attempt: Int) async {
        do {
            let token = try await AuthTokenManager.shared.currentToken(mode: .background)
            await pushAuthToken(token)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning(
                    "Unable to fetch a fresh auth token after BadJWT (attempt \(attempt)): \(error)"
                )
            }
            guard attempt < Self.maxInternalFetchAttempts else { return }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 250_000_000)
            await fetchAndPushFreshToken(attempt: attempt + 1)
        }
    }
}
