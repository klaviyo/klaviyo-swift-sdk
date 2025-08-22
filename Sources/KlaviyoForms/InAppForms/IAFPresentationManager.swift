//
//  IAFPresentationManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/3/25.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog
import UIKit

@MainActor
class IAFPresentationManager {
    // MARK: - Properties & Initializer

    static let shared = IAFPresentationManager()
    private var lastBackgrounded: Date?

    private var lifecycleCancellable: AnyCancellable?
    private var apiKeyCancellable: AnyCancellable?
    private var profileEventCancellable: AnyCancellable?

    private var viewController: KlaviyoWebViewController?
    private var viewModel: IAFWebViewModel?

    private var assetSource: String?

    private var formEventTask: Task<Void, Never>?
    private var initializationWarningTask: Task<Void, Never>?
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

    private var isInitializingOrInitialized: Bool {
        // setting up the API key subscription is the starting point to initializing In-App Forms,
        // and the subscription persists for the entire lifecycle of the form. Therefore,
        // if the apiKeyCancellable has been set then we know that the form is either
        // initializing or initialized.
        apiKeyCancellable != nil
    }

    private init() {}

    #if DEBUG
    package init(viewController: KlaviyoWebViewController?) {
        self.viewController = viewController
    }
    #endif

    func initializeIAF(configuration: InAppFormsConfig, assetSource: String? = nil) {
        guard !isInitializingOrInitialized else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("In-App Form is already either initializing or initialized; ignoring request.")
            }
            return
        }

        self.assetSource = assetSource
        setupApiKeySubscription(configuration)
        setupProfileEventSubscription()
    }

    func createFormAndAwaitFormEvents(apiKey: String) async throws {
        let profileData = try await KlaviyoInternal.fetchProfileData()
        createIAF(apiKey: apiKey, profileData: profileData)
        listenForFormEvents()
    }

    // MARK: - Event Subscriptions

    private func setupApiKeySubscription(_ configuration: InAppFormsConfig) {
        apiKeyCancellable = KlaviyoInternal.apiKeyPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }

                switch result {
                case let .success(apiKey):
                    handleAPIKeyReceived(apiKey, configuration: configuration)
                case let .failure(sdkError):
                    handleAPIKeyError(sdkError)
                }
            }
    }

    private func setupProfileEventSubscription() {
        profileEventCancellable = KlaviyoInternal.eventPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                Task {
                    try? await self.handleProfileEventCreated(event)
                }
            }
    }

    func setupLifecycleEventsSubscription(configuration: InAppFormsConfig) {
        lifecycleCancellable = environment.appLifeCycle.lifeCycleEvents()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .terminated:
                        break
                    case .foregrounded:
                        try await self.handleLifecycleEvent("foreground")
                        if let lastBackgrounded = self.lastBackgrounded {
                            let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
                            let timeoutDuration = configuration.sessionTimeoutDuration
                            if timeElapsed > timeoutDuration {
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
                        try await self.handleLifecycleEvent("background")
                    case .reachabilityChanged:
                        break
                    }
                }
            }
    }

    private func listenForFormEvents() {
        guard let viewModel else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await viewModel.establishHandshake(timeout: NetworkSession.networkTimeout.seconds)
            } catch {
                if #available(iOS 14.0, *) { Logger.webViewLogger.warning("Unable to establish handshake with KlaviyoJS: \(error).") }
                destroyWebviewAndListeners()
            }

            // now that we've established the handshake, we can start a task that listens for Form events.
            self.formEventTask = Task {
                for await event in viewModel.formLifecycleStream {
                    self.handleFormEvent(event)
                }
            }
        }
    }

    // MARK: - Event Handling

    private func handleAPIKeyReceived(_ apiKey: String, configuration: InAppFormsConfig) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Received API key change. New API key: \(apiKey)")
        }

        initializationWarningTask?.cancel()
        initializationWarningTask = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            if viewController != nil {
                if let viewModel, viewModel.apiKey == apiKey {
                    // if viewController/viewModel already exist and the viewModel's
                    // API key matches the one we just received, do nothing
                    return
                } else {
                    await handleAPIKeyChange(apiKey: apiKey, configuration: configuration, assetSource: assetSource)
                }
            } else {
                try await self.createFormAndAwaitFormEvents(apiKey: apiKey)
                setupLifecycleEventsSubscription(configuration: configuration)
            }
        }
    }

    /// Dismisses and re-initializes the In-App Form when the public API key changes.
    private func handleAPIKeyChange(apiKey: String, configuration: InAppFormsConfig, assetSource: String?) async {
        destroyWebView()
        formEventTask?.cancel()
        lifecycleCancellable?.cancel()
        formEventTask = nil
        lifecycleCancellable = nil
        do {
            try await createFormAndAwaitFormEvents(apiKey: apiKey)
            setupLifecycleEventsSubscription(configuration: configuration)
        } catch {
            // TODO: implement catch
            ()
        }
    }

    private func handleAPIKeyError(_ sdkError: SDKError) {
        switch sdkError {
        case .notInitialized:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("SDK is not initialized. Skipping form initialization until the SDK is successfully initialized.")
            }
        case .apiKeyNilOrEmpty:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("SDK API key is empty or nil. Skipping form initialization until a valid API key is received.")
            }
        }

        initializationWarningTask = Task {
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds in nanoseconds
                // Check if task was cancelled before emitting warning
                try Task.checkCancellation()
                environment.emitDeveloperWarning("SDK must be initialized before usage.")
            } catch {
                // Task was cancelled or other error occurred
                return
            }
        }
    }

    private func initializeFormWithAPIKey() async throws {
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        try await createFormAndAwaitFormEvents(apiKey: apiKey)
    }

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

    func handleProfileEventCreated(_ event: Event) async throws {
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

            let result = try await viewController?.evaluateJavaScript("dispatchProfileEvent('\(event.metric.name.value)', \(propertiesJSON))")
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Successfully dispatched event via Klaviyo.JS\(result != nil ? "; message: \(result.debugDescription)" : "")")
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error dispatching event via Klaviyo.JS; message: \(error.localizedDescription)")
            }
        }
    }

    private func handleFormEvent(_ event: IAFLifecycleEvent) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Handling '\(event.rawValue, privacy: .public)' form lifecycle event")
        }
        switch event {
        case .present:
            presentForm()
        case .dismiss:
            dismissForm()
        case .abort:
            destroyWebviewAndListeners()
        }
    }

    // MARK: - Object lifecycle

    /// - Parameter newProfileData: the profile information with which to load the IAF
    private func createIAF(apiKey: String, profileData: ProfileData?) {
        guard let fileUrl = indexHtmlFileUrl else { return }

        let viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData, assetSource: assetSource)
        self.viewModel = viewModel
        viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController?.modalPresentationStyle = .overCurrentContext
    }

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
        lastBackgrounded = nil
        lifecycleCancellable?.cancel()
        apiKeyCancellable?.cancel()
        profileEventCancellable?.cancel()
        formEventTask?.cancel()
        delayedPresentationTask?.cancel()
        lifecycleCancellable = nil
        apiKeyCancellable = nil
        profileEventCancellable = nil
        formEventTask = nil
        delayedPresentationTask = nil
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
        KlaviyoInternal.resetEventSubject()
        destroyWebView()
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
