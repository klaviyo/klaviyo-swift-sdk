//
//  IAFPresentationManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/3/25.
//

import Foundation
import KlaviyoCore
import OSLog
import UIKit

@MainActor
class IAFPresentationManager {
    // MARK: - Properties & Initializer

    static let shared = IAFPresentationManager()

    private var companyObserver: CompanyObserver?
    private var companyEventsTask: Task<Void, Never>?
    private var isInitializingOrInitialized = false

    private var lifecycleObserver: LifecycleObserver?
    private var lifecycleEventsTask: Task<Void, Never>?
    private var lastBackgrounded: Date?

    private var profileEventObserver: ProfileEventObserver?
    private var profileEventsTask: Task<Void, Error>?

    var viewController: KlaviyoWebViewController?
    private(set) var viewModel: IAFWebViewModel?

    private struct PendingTokenDelivery {
        let viewModel: IAFWebViewModel
        let initialToken: String?
        let initialProfile: ProfileData?
        let updates: AsyncStream<String>
        let authTokenManager: AuthTokenManager
    }

    private var pendingTokenDelivery: PendingTokenDelivery?

    private var configuration: InAppFormsConfig?
    private var assetSource: String?

    private var formEventTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var delayedPresentationTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    private var webViewBuildGeneration = 0

    /// Fetches the auth token each new webview is built with; `nil` when none is available.
    var fetchInitialAuthToken: (AuthTokenManager) async -> String? = { authTokenManager in
        await IAFPresentationManager.fetchAuthTokenBestEffort(from: authTokenManager)
    }

    /// Seconds each new webview waits for the KlaviyoJS handshake before it is torn down.
    var handshakeTimeout: TimeInterval = NetworkSession.networkTimeout.seconds

    /// Creates the view controller hosting each new form webview.
    var makeViewController: (IAFWebViewModel) -> KlaviyoWebViewController = { viewModel in
        KlaviyoWebViewController(viewModel: viewModel)
    }

    lazy var indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error loading InAppFormsTemplate.html")
            }
            return nil
        }
    }()

    private init() {}

    #if DEBUG
    package init(viewController: KlaviyoWebViewController?) {
        self.viewController = viewController
    }
    #endif

    // MARK: - Form Lifecycle Handler

    private var formLifecycleHandler: (@MainActor (FormLifecycleEvent) -> Void)?

    func registerFormLifecycleHandler(_ handler: @escaping (FormLifecycleEvent) -> Void) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.log("Registering form lifecycle handler")
        }
        formLifecycleHandler = handler
    }

    func unregisterFormLifecycleHandler() {
        if #available(iOS 14.0, *) {
            if formLifecycleHandler != nil {
                Logger.webViewLogger.log("Unregistering form lifecycle handler")
            }
        }
        formLifecycleHandler = nil
    }

    func invokeLifecycleHandler(for event: FormLifecycleEvent) {
        guard let handler = formLifecycleHandler else { return }

        if #available(iOS 14.0, *) {
            Logger.webViewLogger.debug("Invoking form lifecycle handler for event: \(event.eventName, privacy: .public)")
        }

        handler(event)
    }

    // MARK: - Initialization & Setup

    func initializeIAF(configuration: InAppFormsConfig, assetSource: String? = nil) {
        guard !isInitializingOrInitialized else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("In-App Form is already either initializing or initialized; ignoring request.")
            }
            return
        }

        self.configuration = configuration
        self.assetSource = assetSource

        companyObserver = CompanyObserver()
        companyObserver?.startObserving()
        isInitializingOrInitialized = true

        _ = InAppWindowManager.shared

        companyEventsTask = Task { [weak self] in
            guard let self, let eventsStream = companyObserver?.eventsStream else { return }
            for await event in eventsStream {
                switch event {
                case let .apiKeyUpdated(key):
                    reinitializeIAFForNewAPIKey(key, configuration: configuration)
                case .error:
                    // optionally handle/log
                    break
                }
            }
        }
    }

    @discardableResult
    private func initializeFormWithAPIKey() async throws -> Bool {
        guard let apiKey = SDKConfigStore.shared.current.apiKey, !apiKey.isEmpty else {
            throw SDKError.notInitialized
        }
        return try await createFormWebViewAndListen(apiKey: apiKey)
    }

    /// Builds the form webview and starts listening for its events.
    /// Returns `false` when a newer build or an unregister superseded this one.
    @discardableResult
    func createFormWebViewAndListen(
        apiKey: String,
        authTokenManager: AuthTokenManager = .shared
    ) async throws -> Bool {
        webViewBuildGeneration += 1
        let generation = webViewBuildGeneration
        let tokenUpdates = await authTokenManager.refreshes()
        let fetchedToken = await fetchInitialAuthToken(authTokenManager)
        let authToken = await currentToken(fetchedToken, in: authTokenManager)
        guard generation == webViewBuildGeneration else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Dropping superseded webview build")
            }
            return false
        }
        let profileData = IdentityStore.shared.current
        if let viewModel = createFormWebView(
            apiKey: apiKey,
            profileData: profileData,
            authToken: authToken,
            authTokenManager: authTokenManager
        ) {
            prepareTokenDelivery(
                for: viewModel,
                initialToken: authToken,
                initialProfile: profileData,
                updates: tokenUpdates,
                from: authTokenManager
            )
        }
        setupFormLifecycleListener()
        return true
    }

    /// `token` when it is still the cached token in `authTokenManager`; `nil` when a reset
    /// or replacement cleared it during the wait.
    private func currentToken(_ token: String?, in authTokenManager: AuthTokenManager) async -> String? {
        guard let token, await authTokenManager.isCurrentToken(token) else { return nil }
        return token
    }

    /// Reads the current auth token from ``AuthTokenManager`` for initial WebView
    /// injection. Returns `nil` on any failure — the form proceeds without a token
    /// and the backend serves non-personalized content.
    private static func fetchAuthTokenBestEffort(from authTokenManager: AuthTokenManager) async -> String? {
        // `currentToken()` defaults to `.interactive` mode, which applies the
        // 500ms latency budget appropriate for form display. No external timeout
        // is needed here.
        do {
            let token = try await authTokenManager.currentToken()
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Auth token injected at load")
            }
            return token
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Auth token unavailable at load — proceeding without token")
            }
            return nil
        }
    }

    /// Creates the webview, view model, and view controller for displaying in-app forms.
    /// Returns the new view model, or `nil` when the forms HTML resource is unavailable.
    @discardableResult
    private func createFormWebView(
        apiKey: String,
        profileData: ProfileData?,
        authToken: String?,
        authTokenManager: AuthTokenManager
    ) -> IAFWebViewModel? {
        guard let fileUrl = indexHtmlFileUrl else { return nil }

        let viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: apiKey,
            profileData: profileData,
            authToken: authToken,
            assetSource: assetSource,
            authTokenManager: authTokenManager
        )
        self.viewModel = viewModel
        viewController = makeViewController(viewModel)
        viewController?.modalPresentationStyle = .overCurrentContext
        return viewModel
    }

    /// Records the token stream for `viewModel`'s page, with the token and profile the page
    /// was built with. Delivery starts on ``startTokenDelivery()`` after the handshake.
    /// Cancels any delivery already running for a previous page.
    func prepareTokenDelivery(
        for viewModel: IAFWebViewModel,
        initialToken: String?,
        initialProfile: ProfileData?,
        updates: AsyncStream<String>,
        from authTokenManager: AuthTokenManager
    ) {
        stopTokenDelivery()
        pendingTokenDelivery = PendingTokenDelivery(
            viewModel: viewModel,
            initialToken: initialToken,
            initialProfile: initialProfile,
            updates: updates,
            authTokenManager: authTokenManager
        )
    }

    /// Whether ``IdentityTransition/classify(previous:next:)`` calls the change since the
    /// last delivery a replacement, forcing a token write even if the token value is
    /// unchanged. A `nil` `current` replaces any non-`nil` `previous`.
    static func identityChanged(from previous: ProfileData?, to current: ProfileData?) -> Bool {
        guard let current else { return previous != nil }
        return IdentityTransition.classify(previous: previous, next: current) == .replacement
    }

    /// Pushes each token from the prepared stream into its page. Skips a token equal to the
    /// last one delivered for the page's current profile (starting from the page's initial
    /// token and profile) unless the identity was replaced since, and any token that is no
    /// longer the cached token. A token the page declines (see
    /// ``IAFWebViewModel/pushAuthToken(_:)``) does not count as delivered. Cancelled by
    /// ``prepareTokenDelivery(for:initialToken:initialProfile:updates:from:)`` and
    /// ``destroyWebView()``. No-op when nothing is prepared.
    func startTokenDelivery() {
        guard let pending = pendingTokenDelivery else { return }
        pendingTokenDelivery = nil
        let updates = pending.updates
        let initialToken = pending.initialToken
        let initialProfile = pending.initialProfile
        let authTokenManager = pending.authTokenManager
        tokenRefreshTask = Task { [weak viewModel = pending.viewModel] in
            var deliveredToken = initialToken
            var deliveredIdentity = initialProfile
            for await token in updates {
                guard let viewModel, !Task.isCancelled else { return }
                if token == deliveredToken,
                   !Self.identityChanged(from: deliveredIdentity, to: viewModel.profileData) { continue }
                guard await authTokenManager.isCurrentToken(token) else { continue }
                guard !Task.isCancelled else { return }
                let identity = viewModel.profileData
                guard await viewModel.pushAuthToken(token) else { continue }
                deliveredToken = token
                deliveredIdentity = identity
            }
        }
    }

    // MARK: - Form Lifecycle Listener Setup

    func setupFormLifecycleListener() {
        guard let viewModel else { return }

        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("👂 Starting to listen for form lifecycle events (BEFORE handshake)")
        }

        stopFormEventListening()

        // Start listening for form lifecycle events before handshake to avoid missing any events
        formEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in viewModel.formLifecycleStream {
                self.dispatchFormEvent(event, from: viewModel)
            }
        }

        let handshakeTimeout = handshakeTimeout
        handshakeTask = Task { [weak self] in
            guard let self else { return }
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("🤝 Starting handshake with KlaviyoJS")
            }
            do {
                try await viewModel.establishHandshake(timeout: handshakeTimeout)
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("✅ Handshake completed successfully.")
                }
            } catch {
                if #available(iOS 14.0, *) { Logger.webViewLogger.warning("❌ Unable to establish handshake with KlaviyoJS: \(error).") }
                handleHandshakeFailure(for: viewModel)
            }
        }
    }

    private func stopTokenDelivery() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        pendingTokenDelivery = nil
    }

    private func stopFormEventListening() {
        formEventTask?.cancel()
        formEventTask = nil
        handshakeTask?.cancel()
        handshakeTask = nil
    }

    /// Tears everything down only if `failedViewModel` is still the active view model.
    func handleHandshakeFailure(for failedViewModel: IAFWebViewModel) {
        guard viewModel === failedViewModel else { return }
        destroyWebviewAndListeners()
    }

    /// Handles `event` only if `source` is still the active view model.
    func dispatchFormEvent(_ event: IAFLifecycleEvent, from source: IAFWebViewModel) {
        guard viewModel === source else { return }
        handleFormEvent(event)
    }

    func handleFormEvent(_ event: IAFLifecycleEvent) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Handling '\(event.rawValue, privacy: .public)' form lifecycle event")
        }
        switch event {
        case .handShook:
            // Handshake complete - webview is ready, start observing profile events
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("✅ Handshake confirmed from webview, starting profile observation")
            }
            startProfileObservation()
            startTokenDelivery()
        case let .present(withLayout: layout):
            presentForm(layout: layout)
        case .dismiss:
            dismissForm()
        case .abort:
            destroyWebviewAndListeners()
        }
    }

    // MARK: - Lifecycle Event Handling

    func handleLifecycleEvent(_ event: String) async throws {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Attempting to dispatch '\(event, privacy: .public)' lifecycle event via Klaviyo.JS")
        }

        do {
            let result = try await viewController?.evaluateJavaScript("dispatchLifecycleEvent('\(event)')")
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successfully dispatched lifecycle event via Klaviyo.JS\(result != nil ? "; message: \(result.debugDescription)" : "")")
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error dispatching lifecycle event via Klaviyo.JS; message: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Profile Event Handling

    /// Starts observing profile events from the KlaviyoCore event bus.
    func startProfileObservation() {
        guard profileEventObserver == nil else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("Profile observer already exists; skipping.")
            }
            return
        }

        profileEventObserver = ProfileEventObserver()
        profileEventObserver?.startObserving()

        profileEventsTask = Task { [weak self] in
            guard let self, let eventsStream = profileEventObserver?.eventsStream else { return }
            for await event in eventsStream {
                try await handleProfileEventCreated(event)
            }
        }

        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("👂 Started observing profile events. Buffered events will now be replayed.")
        }
    }

    func handleProfileEventCreated(_ event: Event) async throws {
        guard let viewController = viewController else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("⚠️ Received event but webview is nil (this shouldn't happen)")
            }
            return
        }

        do {
            // Safely convert metric to a JSON string or null
            let metricData = try KlaviyoEnvironment.encoder.encode(event.metric.name.value)
            let metric = String(data: metricData, encoding: .utf8) ?? "null"

            // Safely convert uniqueID to a JSON string or null
            let uniqueIdData = try KlaviyoEnvironment.encoder.encode(event.uniqueId)
            let uniqueId = String(data: uniqueIdData, encoding: .utf8) ?? "null"

            // Convert date to JSON, formatting with ISO8601 (which is always in UTC)
            let timestampData = try KlaviyoEnvironment.encoder.encode(event.time)
            let timestamp = String(data: timestampData, encoding: .utf8) ?? "null"

            // Get event's value as JSON or null
            let valueData = try KlaviyoEnvironment.encoder.encode(event.value)
            let value = String(data: valueData, encoding: .utf8) ?? "null"

            // Convert properties to JSON string to ensure proper object serialization, default to empty dict if serialization fails
            var propertiesJSON = "{}"
            if let propertiesData = try? JSONSerialization.data(withJSONObject: event.properties) {
                propertiesJSON = String(data: propertiesData, encoding: .utf8) ?? propertiesJSON
            }

            // JSON encoding adds the necessary quotes to strings, and escapes unsafe chars, so no need to add add single quotes
            _ = try await viewController.evaluateJavaScript("dispatchProfileEvent(\(metric), \(uniqueId), \(timestamp), \(value), \(propertiesJSON))")
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("❌ Error dispatching event via Klaviyo.JS; message: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - API Key Event Handling

    private func reinitializeIAFForNewAPIKey(_ apiKey: String, configuration: InAppFormsConfig) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("🔄 reinitializeIAFForNewAPIKey called. viewController exists: \(self.viewController != nil)")
            }

            if viewController != nil {
                if let viewModel, viewModel.apiKey == apiKey {
                    // if viewController/viewModel already exist and the viewModel's
                    // API key matches the one we just received, do nothing
                    if #available(iOS 14.0, *) {
                        Logger.webViewLogger.info("✅ Webview already exists with same API key, skipping reinit")
                    }
                    return
                } else {
                    await handleAPIKeyChange(apiKey: apiKey, configuration: configuration, assetSource: assetSource)
                }
            } else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("🆕 Creating new webview and establishing handshake")
                }
                try await self.createFormWebViewAndListen(apiKey: apiKey)
                if isInitializingOrInitialized {
                    startLifecycleObservation()
                }
            }
        }
    }

    /// Dismisses and re-initializes the In-App Form when the public API key changes.
    private func handleAPIKeyChange(apiKey: String, configuration: InAppFormsConfig, assetSource: String?) async {
        destroyWebView()
        stopFormEventListening()
        lifecycleObserver?.stopObserving()
        profileEventObserver?.stopObserving()
        profileEventObserver = nil
        profileEventsTask?.cancel()
        profileEventsTask = nil

        do {
            try await createFormWebViewAndListen(apiKey: apiKey)
            if isInitializingOrInitialized {
                startLifecycleObservation()
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Failed to reinitialize form after API key change: \(error.localizedDescription)")
            }
        }
    }

    func startLifecycleObservation() {
        let observer = LifecycleObserver()
        observer.startObserving()
        lifecycleObserver = observer
        let eventsStream = observer.eventsStream
        lifecycleEventsTask = Task { [weak self] in
            for await event in eventsStream {
                guard let self else { return }
                await self.handleAppLifecycleEvent(event)
            }
        }
    }

    /// Handles a single app-lifecycle event. Catches its own errors so that a failure
    /// handling one event (e.g. a transient `initializeFormWithAPIKey()` throw) can never
    /// break out of the observation loop and silently disable session-expiry detection
    /// for the rest of the process lifetime.
    func handleAppLifecycleEvent(_ event: LifecycleObserver.Event) async {
        do {
            switch event {
            case .foregrounded:
                try await handleForegrounded()
            case .backgrounded:
                lastBackgrounded = Date()
                try await handleLifecycleEvent("background")
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning(
                    "Error handling app lifecycle event: \(error.localizedDescription)"
                )
            }
        }
    }

    private func handleForegrounded() async throws {
        try await handleLifecycleEvent("foreground")
        if lastBackgrounded != nil {
            if isSessionExpired {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("App session has exceeded timeout duration; re-initializing IAF")
                }
                tearDownFormWebView()
                try await initializeFormWithAPIKey()
            }
            // Consume the handled transition so a later foreground without a real
            // background isn't mis-read as expired.
            lastBackgrounded = nil
        } else {
            // When opening Notification/Control Center, the system will not dispatch a `backgrounded` event,
            // but it will dispatch a `foregrounded` event when Notification/Control Center is dismissed.
            // This check ensures that don't reinitialize in this situation.
            if viewController == nil {
                // fresh launch
                try await initializeFormWithAPIKey()
            }
        }
    }

    private var isSessionExpired: Bool {
        guard let lastBackgrounded, let timeoutDuration = configuration?.sessionTimeoutDuration else { return false }
        let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
        return timeElapsed > timeoutDuration
    }

    // MARK: - View Lifecycle

    private func presentForm(layout: FormLayout?) {
        guard let viewController else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("KlaviyoWebViewController is nil; ignoring `presentForm()` request")
            }
            return
        }

        if let layout, layout.position != .fullscreen {
            // Flexible form: use window manager
            delayedPresentationTask?.cancel()
            delayedPresentationTask = nil
            InAppWindowManager.shared.present(viewController: viewController, layout: layout)
        } else {
            // Fullscreen form: use modal presentation
            presentFormAsModal(viewController: viewController)
        }
    }

    private func presentFormAsModal(viewController: KlaviyoWebViewController) {
        guard let topController = UIApplication.shared.topMostViewController else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Unable to access topMostViewController; ignoring `presentForm()` request.")
            }
            self.viewController = nil
            return
        }

        if topController is UIAlertController {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Alert is currently being displayed. Delaying form presentation until alert is dismissed.")
            }

            // We'll recursively call `presentForm()` after a short delay.
            // Cancel any in-flight delayed task before starting a new one.
            delayedPresentationTask?.cancel()
            delayedPresentationTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                try? Task.checkCancellation()
                self.presentForm(layout: nil)
            }
        } else {
            if topController.isKlaviyoVC || topController.hasKlaviyoVCInStack {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("In-App Form is already being presented; ignoring request")
                }
            } else {
                topController.present(viewController, animated: false, completion: nil)
            }
        }
    }

    func dismissForm() {
        guard let viewController else { return }
        performDismiss(viewController: viewController)
    }

    // MARK: - Cleanup & Destruction

    func destroyWebView() {
        // Cancel before the guard: `viewController` may already have been cleared
        // elsewhere (e.g. a failed presentation) while the token-refresh task is
        // still running, so gating the cancel on `viewController` would leak it.
        stopTokenDelivery()

        guard let viewController else { return }

        performDismiss(viewController: viewController)

        self.viewController = nil
        viewModel = nil
    }

    private func performDismiss(viewController: KlaviyoWebViewController) {
        if InAppWindowManager.shared.hasActiveWindow {
            // Flexible form: dismiss window
            InAppWindowManager.shared.dismiss()
        } else {
            // Fullscreen form: dismiss modal
            viewController.dismiss(animated: false, completion: nil)
        }
    }

    /// Tears down only the web-view-scoped state: the webview, its view model, and the
    /// form + profile-event listeners tied to that webview. Leaves app-lifecycle and
    /// company (API-key) observation intact so the form can be rebuilt in place (e.g.
    /// after a session timeout) without the host app needing to re-register. Contrast with
    /// `destroyWebviewAndListeners()`, the full unregister path.
    func tearDownFormWebView() {
        profileEventObserver?.stopObserving()
        profileEventObserver = nil
        profileEventsTask?.cancel()
        profileEventsTask = nil
        stopFormEventListening()
        delayedPresentationTask?.cancel()
        delayedPresentationTask = nil
        destroyWebView()
    }

    func destroyWebviewAndListeners() {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("UnregisterFromInAppForms; destroying webview and listeners")
        }
        isInitializingOrInitialized = false
        webViewBuildGeneration += 1
        lifecycleObserver = nil
        companyObserver = nil
        tearDownFormWebView()
    }
}

// MARK: - UI helpers

extension UIViewController {
    fileprivate var isKlaviyoVC: Bool {
        self is KlaviyoWebViewController
    }

    fileprivate var hasKlaviyoVCInStack: Bool {
        guard let navigationController = navigationController else {
            return false
        }
        return navigationController.viewControllers.contains(where: \.isKlaviyoVC)
    }
}
