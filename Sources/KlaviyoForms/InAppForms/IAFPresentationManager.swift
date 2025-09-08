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

    private let companyObserver = CompanyObserver()
    private var companyEventsTask: Task<Void, Never>?
    private var isInitializingOrInitialized = false

    private var lifecycleObserver = LifecycleObserver()
    private var lifecycleEventsTask: Task<Void, Error>?
    private var lastBackgrounded: Date?

    private var viewController: KlaviyoWebViewController?
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

        companyObserver.startObserving()
        isInitializingOrInitialized = true

        companyEventsTask = Task { [weak self] in
            guard let self, let eventsStream = companyObserver.eventsStream else { return }
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

    func createFormAndAwaitFormEvents(apiKey: String) async throws {
        let profileData = try await KlaviyoInternal.fetchProfileData()
        createIAF(apiKey: apiKey, profileData: profileData)
        listenForFormEvents()
    }

    private func initializeFormWithAPIKey() async throws {
        let apiKey = try await KlaviyoInternal.fetchAPIKey()
        try await createFormAndAwaitFormEvents(apiKey: apiKey)
    }

    /// - Parameter newProfileData: the profile information with which to load the IAF
    private func createIAF(apiKey: String, profileData: ProfileData?) {
        guard let fileUrl = indexHtmlFileUrl else { return }

        let viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData, assetSource: assetSource)
        self.viewModel = viewModel
        viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController?.modalPresentationStyle = .overCurrentContext
    }

    // MARK: - Form Event Subscription

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

    // There are cases when a `foreground` event may be dispatched even if there was not a `background` event
    // such as the case when the Notification/Control Center is opened. We want to ensure we do not mistakenly
    // re-initialize in that case
    func handleInSessionForegroundEvent() async throws {
        if viewController == nil {
            // fresh launch
            try await initializeFormWithAPIKey()
        }
    }

    // MARK: - API Key Event Handling

    func reinitializeIAFForNewAPIKey(_ apiKey: String, configuration: InAppFormsConfig) {
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
                startLifecycleObservation()
            }
        }
    }

    /// Dismisses and re-initializes the In-App Form when the public API key changes.
    private func handleAPIKeyChange(apiKey: String, configuration: InAppFormsConfig, assetSource: String?) async {
        destroyWebView()
        formEventTask?.cancel()
        formEventTask = nil
        lifecycleObserver.stopObserving()
        do {
            try await createFormAndAwaitFormEvents(apiKey: apiKey)
            startLifecycleObservation()
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Failed to reinitialize form after API key change: \(error.localizedDescription)")
            }
        }
    }

    private func startLifecycleObservation() {
        lifecycleEventsTask = Task { [weak self] in
            guard let self, let eventsStream = lifecycleObserver.eventsStream else { return }
            for await event in eventsStream {
                switch event {
                case .backgrounded:
                    self.lastBackgrounded = Date()
                    try? await self.handleLifecycleEvent("background")
                case .foregrounded:
                    try await self.handleLifecycleEvent("foreground")
                    if let lastBackgrounded = self.lastBackgrounded {
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
                }
            }
        }
        lifecycleObserver.startObserving()
    }

    private var isSessionExpired: Bool {
        guard let lastBackgrounded, let timeoutDuration = configuration?.sessionTimeoutDuration else { return false }
        let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
        return timeElapsed > timeoutDuration
    }

    func reinitializeInAppForms() async throws {
        destroyWebView()
        try await initializeFormWithAPIKey()
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
        lifecycleObserver.stopObserving()
        companyObserver.stopObserving()
        formEventTask?.cancel()
        delayedPresentationTask?.cancel()
        formEventTask = nil
        delayedPresentationTask = nil
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
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
