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

    private var viewController: KlaviyoWebViewController?
    private var viewModel: IAFWebViewModel?

    private var assetSource: String?

    private var formEventTask: Task<Void, Never>?
    private var initializationWarningTask: Task<Void, Never>?

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

    func initializeIAF(configuration: IAFConfiguration, assetSource: String? = nil) {
        guard !isInitializingOrInitialized else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("In-App Form is already either initializing or initialized; ignoring request.")
            }
            return
        }

        self.assetSource = assetSource
        setupApiKeySubscription(configuration)
    }

    func createFormAndAwaitFormEvents(assetSource: String? = nil) async throws {
        let profileData = try await KlaviyoInternal.fetchProfileData()
        createIAF(profileData: profileData, assetSource: assetSource)
        listenForFormEvents()
    }

    // MARK: - Event Subscriptions

    private func setupApiKeySubscription(_ configuration: IAFConfiguration) {
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

    func setupLifecycleEventsSubscription(configuration: IAFConfiguration) {
        lifecycleCancellable = environment.appLifeCycle.lifeCycleEvents()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .terminated:
                        break
                    case .foregrounded:
                        if let lastBackgrounded = self.lastBackgrounded {
                            let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
                            let timeoutDuration = configuration.sessionTimeoutDuration
                            try await self.handleLifecycleEvent("foreground", additionalAction: {
                                // new session
                                if timeElapsed > timeoutDuration {
                                    self.destroyWebView()
                                    try await self.createFormAndAwaitFormEvents()
                                }
                            })
                        } else {
                            // launching
                            try await self.handleLifecycleEvent("foreground", additionalAction: {
                                try await self.createFormAndAwaitFormEvents()
                            })
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

    @MainActor
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

    private func handleAPIKeyReceived(_ apiKey: String, configuration: IAFConfiguration) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Received API key change. New API key: \(apiKey)")
        }

        initializationWarningTask?.cancel()
        initializationWarningTask = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            if viewController != nil {
                if let viewModel, viewModel.profileData.apiKey == apiKey {
                    // if viewController/viewModel already exist and the viewModel's
                    // API key matches the one we just received, do nothing
                    return
                } else {
                    await handleAPIKeyChange(apiKey: apiKey, configuration: configuration, assetSource: assetSource)
                }
            } else {
                try await self.createFormAndAwaitFormEvents(assetSource: self.assetSource)
                setupLifecycleEventsSubscription(configuration: configuration)
            }
        }
    }

    /// Dismisses and re-initializes the in-app form when the user's profile information changes.
    @MainActor
    private func handleAPIKeyChange(apiKey: String, configuration: IAFConfiguration, assetSource: String?) async {
        destroyWebView()
        formEventTask?.cancel()
        lifecycleCancellable?.cancel()
        formEventTask = nil
        lifecycleCancellable = nil
        do {
            try await createFormAndAwaitFormEvents()
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
                Logger.webViewLogger.info("Received profile state change event, but SDK is not initialized. Skipping form initialization until the SDK is successfully initialized.")
            }
        case .apiKeyNilOrEmpty:
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("Received profile state change event, but the SDK API key is empty or nil. Skipping form initialization until a valid API key is received.")
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

    func handleLifecycleEvent(_ event: String, additionalAction: (() async throws -> Void)? = nil) async throws {
        do {
            let result = try await viewController?.evaluateJavaScript("dispatchLifecycleEvent('\(event)')")
            if let successMessage = result as? String {
                print("Successfully evaluated Javascript; message: \(successMessage)")
            }
            if let additionalAction = additionalAction {
                try await additionalAction()
            }
        } catch {
            print("Javascript evaluation failed; message: \(error.localizedDescription)")
        }
    }

    private func handleFormEvent(_ event: IAFLifecycleEvent) {
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
    @MainActor
    private func createIAF(profileData: ProfileData, assetSource: String?) {
        guard let fileUrl = indexHtmlFileUrl else { return }

        let viewModel = IAFWebViewModel(url: fileUrl, profileData: profileData, assetSource: assetSource)
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
        formEventTask?.cancel()
        lifecycleCancellable = nil
        apiKeyCancellable = nil
        formEventTask = nil
        KlaviyoInternal.resetProfileDataSubject()
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

        if topController.isKlaviyoVC || topController.hasKlaviyoVCInStack {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("In-App Form is already being presented; ignoring request")
            }
            destroyWebView()
        } else {
            topController.present(viewController, animated: false, completion: nil)
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
