//
//  IAFPresentationManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/3/25.
//

import Foundation
import KlaviyoCore
import KlaviyoSwift
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
    private var lifecycleEventsTask: Task<Void, Error>?
    private var lastBackgrounded: Date?

    private var profileEventObserver: ProfileEventObserver?
    private var profileEventsTask: Task<Void, Error>?

    var viewController: KlaviyoWebViewController?
    private var viewModel: IAFWebViewModel?

    private var configuration: InAppFormsConfig?
    private var assetSource: String?

    private var formEventTask: Task<Void, Never>?
    private var delayedPresentationTask: Task<Void, Never>?

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

    private func initializeFormWithAPIKey() async throws {
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        try await createFormWebViewAndListen(apiKey: apiKey)
    }

    func createFormWebViewAndListen(apiKey: String) async throws {
        let profileData = try await KlaviyoInternal.fetchProfileData()
        createFormWebView(apiKey: apiKey, profileData: profileData)
        setupFormLifecycleListener()
    }

    /// Creates the webview, view model, and view controller for displaying in-app forms
    private func createFormWebView(apiKey: String, profileData: ProfileData?) {
        guard let fileUrl = indexHtmlFileUrl else { return }

        let viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData, assetSource: assetSource)
        self.viewModel = viewModel
        viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController?.modalPresentationStyle = .overCurrentContext
    }

    // MARK: - Form Lifecycle Listener Setup

    func setupFormLifecycleListener() {
        guard let viewModel else { return }

        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("👂 Starting to listen for form lifecycle events (BEFORE handshake)")
        }

        // Start listening for form lifecycle events before handshake to avoid missing any events
        formEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in viewModel.formLifecycleStream {
                self.handleFormEvent(event)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("🤝 Starting handshake with KlaviyoJS")
            }
            do {
                try await viewModel.establishHandshake(timeout: NetworkSession.networkTimeout.seconds)
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("✅ Handshake completed successfully.")
                }
            } catch {
                if #available(iOS 14.0, *) { Logger.webViewLogger.warning("❌ Unable to establish handshake with KlaviyoJS: \(error).") }
                destroyWebviewAndListeners()
            }
        }
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
        case .present:
            presentForm()
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

    /// Starts observing profile events from KlaviyoInternal.
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
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("📨 Received event '\(event.metric.name.value, privacy: .public)'")
        }

        guard let viewController = viewController else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("⚠️ Received event but webview is nil (this shouldn't happen)")
            }
            return
        }

        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Attempting to dispatch '\(event.metric.name.value, privacy: .public)' event via Klaviyo.JS")
        }

        do {
            // Convert properties to JSON string to ensure proper object serialization
            let propertiesJSON: String
            if let propertiesData = try? JSONSerialization.data(withJSONObject: event.properties),
               let propertiesString = String(data: propertiesData, encoding: .utf8) {
                propertiesJSON = propertiesString
            } else {
                // Fallback to empty object if serialization fails
                propertiesJSON = "{}"
            }

            let result = try await viewController.evaluateJavaScript("dispatchProfileEvent('\(event.metric.name.value)', \(propertiesJSON))")
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("✅ Successfully dispatched event via Klaviyo.JS\(result != nil ? "; message: \(result.debugDescription)" : "")")
            }
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
                startLifecycleObservation()
            }
        }
    }

    /// Dismisses and re-initializes the In-App Form when the public API key changes.
    private func handleAPIKeyChange(apiKey: String, configuration: InAppFormsConfig, assetSource: String?) async {
        destroyWebView()
        formEventTask?.cancel()
        formEventTask = nil
        lifecycleObserver?.stopObserving()
        profileEventObserver?.stopObserving()
        profileEventObserver = nil
        profileEventsTask?.cancel()
        profileEventsTask = nil
        KlaviyoInternal.resetEventSubject()

        do {
            try await createFormWebViewAndListen(apiKey: apiKey)
            startLifecycleObservation()
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Failed to reinitialize form after API key change: \(error.localizedDescription)")
            }
        }
    }

    func startLifecycleObservation() {
        lifecycleObserver = LifecycleObserver()
        lifecycleObserver?.startObserving()
        lifecycleEventsTask = Task { [weak self] in
            guard let self, let eventsStream = lifecycleObserver?.eventsStream else { return }
            for await event in eventsStream {
                switch event {
                case .foregrounded:
                    try await self.handleLifecycleEvent("foreground")
                    if self.lastBackgrounded != nil {
                        if isSessionExpired {
                            if #available(iOS 14.0, *) {
                                Logger.webViewLogger.info("App session has exceeded timeout duration; re-initializing IAF")
                            }
                            self.destroyWebView()
                            try await self.initializeFormWithAPIKey()
                        }
                    } else {
                        // When opening Notification/Control Center, the system will not dispatch a `backgrounded` event,
                        // but it will dispatch a `foregrounded` event when Notification/Control Center is dismissed.
                        // This check ensures that don't reinitialize in this situation.
                        if self.viewController == nil {
                            // fresh launch
                            try await self.initializeFormWithAPIKey()
                        }
                    }
                case .backgrounded:
                    self.lastBackgrounded = Date()
                    try? await self.handleLifecycleEvent("background")
                }
            }
        }
    }

    private var isSessionExpired: Bool {
        guard let lastBackgrounded, let timeoutDuration = configuration?.sessionTimeoutDuration else { return false }
        let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
        return timeElapsed > timeoutDuration
    }

    // MARK: - View Lifecycle

    private func presentForm() {
        guard let viewController else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("KlaviyoWebViewController is nil; ignoring `presentForm()` request")
            }
            return
        }

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
            delayedPresentationTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                try? Task.checkCancellation()
                self.presentForm()
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
        viewController.dismiss(animated: false)
    }

    // MARK: - Cleanup & Destruction

    func destroyWebView() {
        guard let viewController else { return }

        viewController.dismiss(animated: false, completion: nil)

        self.viewController = nil
        viewModel = nil
    }

    func destroyWebviewAndListeners() {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("UnregisterFromInAppForms; destroying webview and listeners")
        }
        isInitializingOrInitialized = false
        lifecycleObserver = nil
        companyObserver = nil
        profileEventObserver = nil
        profileEventsTask?.cancel()
        formEventTask?.cancel()
        delayedPresentationTask?.cancel()
        formEventTask = nil
        delayedPresentationTask = nil
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
        KlaviyoInternal.resetEventSubject()
        destroyWebView()
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
