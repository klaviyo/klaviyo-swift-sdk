//
//  IAFWebViewModel.swift
//  TestApp
//
//  Created by Andrew Balmer on 1/27/25.
//

import Combine
import Foundation
import KlaviyoCore
import OSLog
import WebKit

// swiftlint:disable:next type_body_length
class IAFWebViewModel: KlaviyoWebViewModeling {
    private enum MessageHandler: String, CaseIterable {
        case klaviyoNativeBridge = "KlaviyoNativeBridge"
    }

    // MARK: - Properties

    private static let maxIdentityTokenFetchAttempts = 3

    weak var delegate: KlaviyoWebViewDelegate?

    let url: URL
    var loadScripts: Set<WKUserScript>? = Set<WKUserScript>()
    let messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    let apiKey: String
    /// The most recent profile written to the page, via the load script or a live update.
    private(set) var profileData: ProfileData?
    /// The auth token a page load injects. `nil` after an identity replacement until a token
    /// for the new profile is pushed.
    private(set) var authToken: String?
    private let assetSource: String?
    private let authTokenManager: AuthTokenManager

    private var identityUserScript: WKUserScript?

    private var profileUpdatesCancellable: AnyCancellable?
    /// The task writing the latest profile change to the page and, after an identity
    /// replacement, clearing token state and fetching a token for the new profile.
    private(set) var profileUpdateTask: Task<Void, Never>?
    /// The latest identity replacement's profile write and token-state clear, until both
    /// finish. ``pushAuthToken(_:)`` waits for it.
    private var pendingIdentityReplacement: Task<Void, Never>?
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

    /// Writes ``profileData`` and then ``authToken`` to the page in one script, so the token
    /// always reaches a loading page after the profile it belongs to.
    @MainActor
    private var identityWKScript: WKUserScript? {
        let profileScript = profileData.flatMap { createProfileAttributesScript(from: $0) }
        let authTokenScript = authToken.map { createAuthTokenScript(from: $0) }
        let source = [profileScript, authTokenScript].compactMap { $0 }.joined(separator: "\n")
        guard !source.isEmpty else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
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
        assetSource: String? = nil,
        authTokenManager: AuthTokenManager = .shared
    ) {
        self.url = url
        self.apiKey = apiKey
        self.profileData = profileData
        self.authToken = authToken
        self.assetSource = assetSource
        self.authTokenManager = authTokenManager

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
        replaceLoadScript(&identityUserScript, with: identityWKScript)
        if let dataEnvironmentWKScript {
            loadScripts?.insert(dataEnvironmentWKScript)
        }
    }

    /// Swaps `current` for `replacement` in ``loadScripts`` so a page load that has not
    /// happened yet injects the latest value.
    @MainActor
    private func replaceLoadScript(_ current: inout WKUserScript?, with replacement: WKUserScript?) {
        if let current {
            loadScripts?.remove(current)
        }
        current = replacement
        if let replacement {
            loadScripts?.insert(replacement)
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
        profileUpdatesCancellable = IdentityStore.shared.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newProfileData in
                guard let self else { return }

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

    /// Writes `newProfileData` to the page. When ``IdentityTransition/classify(previous:next:)``
    /// calls the change a replacement, onsite discards its auth token, so the outgoing token
    /// is dropped from the load scripts, the profile is written, the manager's token state is
    /// cleared, and a token for the new profile is fetched; the fetch publishes it to
    /// ``IAFPresentationManager``'s token delivery. The token step runs even when no profile
    /// script can be built. Other transitions keep the current token.
    @MainActor
    private func handleProfileDataChange(_ newProfileData: ProfileData) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Attempting to update In-App Forms HTML with updated profile data")
        }
        let transition = IdentityTransition.classify(previous: profileData, next: newProfileData)
        profileData = newProfileData
        if transition == .replacement {
            authToken = nil
        }
        replaceLoadScript(&identityUserScript, with: identityWKScript)
        let profileAttributesScript = createProfileAttributesScript(from: newProfileData)

        guard transition == .replacement else {
            if let profileAttributesScript {
                profileUpdateTask = Task { @MainActor [weak self] in
                    await self?.writeProfileAttributes(profileAttributesScript)
                }
            }
            return
        }

        let authTokenManager = authTokenManager
        let replacement = Task { @MainActor [weak self] in
            if let profileAttributesScript {
                await self?.writeProfileAttributes(profileAttributesScript)
            }
            await authTokenManager.clearReplacedProfileTokenState()
        }
        pendingIdentityReplacement = replacement
        profileUpdateTask = Task { @MainActor [weak self] in
            await replacement.value
            guard let self else { return }
            if pendingIdentityReplacement == replacement {
                pendingIdentityReplacement = nil
            }
            await refreshAuthToken(for: newProfileData)
        }
    }

    @MainActor
    private func writeProfileAttributes(_ script: String) async {
        do {
            let result = try await delegate?.evaluateJavaScript(script)
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successfully updated In-App Forms HTML with updated profile data; message: \(result.debugDescription)")
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error updating In-App Forms HTML; error: \(error)")
            }
        }
    }

    /// Fetches a token for `identity` from the registered provider, so the fetch publishes it
    /// on ``AuthTokenManager/refreshes()``. Stops once a later change replaced `identity`. A
    /// fetch that is cancelled, or whose identity generation moves before this returns, is
    /// retried, up to ``maxIdentityTokenFetchAttempts`` attempts in total. Other failures are
    /// logged.
    @MainActor
    private func refreshAuthToken(for identity: ProfileData) async {
        for _ in 0..<Self.maxIdentityTokenFetchAttempts {
            guard isCompatibleWithPage(identity) else { return }
            do {
                let refresh = try await authTokenManager.currentTokenRefresh(mode: .background)
                if refresh.generation == authTokenManager.currentIdentityGeneration { return }
            } catch where error.isFetchCancellation {
                continue
            } catch AuthTokenError.noProfileIdentifier {
                return
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("Auth token unavailable after profile change; error: \(error)")
                }
                return
            }
        }
    }

    /// `true` while the page's profile still describes the same person as `identity`.
    @MainActor
    private func isCompatibleWithPage(_ identity: ProfileData) -> Bool {
        IdentityTransition.classify(previous: identity, next: profileData ?? identity) != .replacement
    }

    /// `true` while ``IdentityStore`` holds an identity that replaces the page's profile and
    /// the page has not processed the change yet.
    @MainActor
    private var isPageBehindIdentityStore: Bool {
        IdentityTransition.classify(previous: profileData, next: IdentityStore.shared.current) == .replacement
    }

    // MARK: - Handle token refreshes

    /// Pushes a refreshed auth token into the live page, updating the
    /// `data-klaviyo-jwt` head attribute so onsite re-reads the new token without
    /// a reload. Driven by ``IAFPresentationManager``'s token delivery, which owns the
    /// `AuthTokenManager.refreshes()` stream for the WebView's lifetime; this method is
    /// the per-token push, mirroring ``pushDeviceInfo()``. Also replaces the token load
    /// script, so a page that has not loaded yet starts with this token.
    ///
    /// Never writes a token ahead of the profile it belongs to. While an identity
    /// replacement's profile write and token-state clear are running, waits for them and
    /// then writes `token` only if `generation` (by default, the manager's current one) is
    /// still the manager's current identity generation. Declines when ``IdentityStore``
    /// already holds an identity that replaces the page's profile.
    ///
    /// `async` so the caller can await it and apply refreshes in arrival order.
    /// The token value is never logged — only the success/failure of the update.
    /// - Returns: `true` when `token` was written, `false` when the push was declined.
    @MainActor
    @discardableResult
    func pushAuthToken(_ token: String, generation: UInt64? = nil) async -> Bool {
        let generation = generation ?? authTokenManager.currentIdentityGeneration
        guard generation == authTokenManager.currentIdentityGeneration else { return false }
        var awaitedReplacement: Task<Void, Never>?
        while let replacement = pendingIdentityReplacement, replacement != awaitedReplacement {
            await replacement.value
            awaitedReplacement = replacement
            guard generation == authTokenManager.currentIdentityGeneration else { return false }
        }
        guard !isPageBehindIdentityStore else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Holding auth token until the profile change reaches In-App Forms")
            }
            return false
        }
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Auth token refreshed; updating In-App Forms HTML")
        }
        authToken = token
        replaceLoadScript(&identityUserScript, with: identityWKScript)
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
        return true
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
                EventDispatcher.shared.dispatch(
                    .createEvent(Event(name: .customEvent(metricName), properties: jsonEventData))
                )
            }
        case let .trackAggregateEvent(data):
            EventDispatcher.shared.dispatch(.aggregateEvent(data))
        case let .openDeepLink(url, formId, formName, buttonLabel, openExternally):
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info(
                    """
                    Received 'openDeepLink' event from KlaviyoJS with url: \
                    \(url?.absoluteString ?? "nil", privacy: .private), \
                    openExternally: \(openExternally, privacy: .public)
                    """
                )
            }

            // 1. Check URL exists and is non-empty — no URL means no navigation and no lifecycle event
            guard let url = url, !url.absoluteString.isEmpty else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning(
                        "CTA clicked but no URL configured — skipping navigation"
                    )
                }
                return
            }

            // 2. Route by `openExternally`. Deep links and external URLs ride the same
            //    bridge message (onsite openDeepLink v3); the flag — not the scheme —
            //    decides how to open, preserving the marketer's chosen action.
            if openExternally {
                // External web/system URL: open via the system, bypassing any registered
                // deep link handler, gated by the on-device scheme allowlist.
                guard let scheme = url.scheme?.lowercased(), openUrlAllowedSchemes.contains(scheme) else {
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.warning(
                            "Blocked external URL with disallowed scheme: \(url.scheme ?? "nil", privacy: .public)"
                        )
                    }
                    return
                }
                Task {
                    await environment.linkHandler.openExternalURL(url)
                }
            } else {
                // In-app deep link: route to the host app's registered deep link handler.
                if UIApplication.shared.canOpenURL(url) {
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.info("Attempting to open URL '\(url, privacy: .private)'")
                    }
                    EventDispatcher.shared.dispatch(.deepLink(url))
                } else {
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.warning("Unable to open the URL '\(url, privacy: .private)'. This may be because a) the device does not have an installed app registered to handle the URL's scheme, or b) you haven't declared the URL's scheme in your Info.plist file")
                    }
                    // No navigation occurred — skip the formCtaClicked lifecycle event below,
                    // consistent with its "fired after the SDK has initiated navigation" contract.
                    return
                }
            }

            // 3. Invoke lifecycle handler when form identity fields are present. Both deep
            //    links and external URLs surface through the same formCtaClicked event; the
            //    URL rides in the deepLinkUrl field.
            invokeCtaLifecycleHandler(eventName: "openDeepLink", formId: formId, formName: formName) {
                .formCtaClicked(
                    formId: $0,
                    formName: $1,
                    buttonLabel: buttonLabel ?? "",
                    deepLinkUrl: url
                )
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
        case .refreshJwt:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received 'refreshJwt' event from KlaviyoJS")
            }
            Task { [authTokenManager] in
                await authTokenManager.refreshRejectedToken()
            }
        }
    }

    /// Invokes the form lifecycle handler for a CTA tap when form identity fields are present.
    /// buttonLabel is allowed to be nil/empty — a CTA with no text is still a valid click.
    @MainActor
    private func invokeCtaLifecycleHandler(
        eventName: String,
        formId: String?,
        formName: String?,
        makeEvent: (_ formId: String, _ formName: String) -> FormLifecycleEvent
    ) {
        guard let formId, !formId.isEmpty,
              let formName, !formName.isEmpty else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning(
                    "\(eventName, privacy: .public) missing metadata — skipping lifecycle callback"
                )
            }
            return
        }
        IAFPresentationManager.shared.invokeLifecycleHandler(for: makeEvent(formId, formName))
    }
}

extension Error {
    /// `true` for the error a token fetch surfaces when it is cancelled, whether thrown by
    /// Swift concurrency or by a `URLSession`-backed provider.
    fileprivate var isFetchCancellation: Bool {
        if self is CancellationError { return true }
        return (self as? URLError)?.code == .cancelled
    }
}
