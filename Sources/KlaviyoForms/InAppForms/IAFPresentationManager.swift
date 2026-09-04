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

/// Coordinates the In-App Forms feature.
///
/// Owns the things that live for the whole process — the API-key and app-lifecycle observers,
/// the configuration, the presenter — and holds at most one ``FormsSession`` at a time.
///
/// Session teardown is `session = nil`. Everything scoped to a session lives on `FormsSession`
/// and is released with it, so rebuilding (API-key change, session timeout) cannot leave part
/// of the old session behind.
@MainActor
class IAFPresentationManager {
    // MARK: - Properties & Initializer

    static let shared = IAFPresentationManager()

    /// The active forms session, if any. Assigning `nil` tears the previous one down.
    private var session: FormsSession?

    private let presenter = IAFPresenter()

    private var companyObserver: CompanyObserver?
    private var companyEventsTask: Task<Void, Never>?
    private var isInitializingOrInitialized = false

    private var lifecycleObserver: LifecycleObserver?
    private var lifecycleEventsTask: Task<Void, Never>?
    private var lastBackgrounded: Date?

    private var configuration: InAppFormsConfig?
    private var assetSource: String?

    private init() {}

    // MARK: - Form Lifecycle Handler

    func registerFormLifecycleHandler(_ handler: @escaping (FormLifecycleEvent) -> Void) {
        FormLifecycleHandlerRegistry.shared.register(handler)
    }

    func unregisterFormLifecycleHandler() {
        FormLifecycleHandlerRegistry.shared.unregister()
    }

    func invokeLifecycleHandler(for event: FormLifecycleEvent) {
        FormLifecycleHandlerRegistry.shared.invoke(for: event)
    }

    // MARK: - Initialization & Setup

    func initializeIAF(configuration: InAppFormsConfig, assetSource: String? = nil) {
        guard !isInitializingOrInitialized else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log(
                    "In-App Form is already either initializing or initialized; ignoring request."
                )
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
                case let .apiKeyUpdated(apiKey):
                    handleAPIKey(apiKey)
                case .error:
                    // optionally handle/log
                    break
                }
            }
        }
    }

    /// Handles the API key becoming available or changing.
    ///
    /// Note this fires with the *current* value when the observer subscribes, not only on a
    /// change, so this is also the path that builds the very first session.
    private func handleAPIKey(_ apiKey: String) {
        if let session {
            guard session.apiKey != apiKey else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("✅ Session already exists with same API key, skipping reinit")
                }
                return
            }
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("🔄 API key changed; rebuilding forms session")
            }
        } else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("🆕 Creating new webview and establishing handshake")
            }
        }

        startSession(apiKey: apiKey)
        startLifecycleObservation()
    }

    /// Builds a fresh session, releasing any previous one.
    private func startSession(apiKey: String) {
        presenter.cancelDelayedPresentation()

        // Releasing the old session tears down its webview, observer and tasks.
        session = nil

        session = FormsSession(
            apiKey: apiKey,
            assetSource: assetSource,
            callbacks: FormsSession.Callbacks(
                present: { [weak self] viewController, layout in
                    self?.presenter.present(viewController, layout: layout)
                },
                dismiss: { [weak self] viewController in
                    self?.presenter.dismiss(viewController)
                },
                abort: { [weak self] in
                    self?.endSession()
                }
            )
        )
    }

    /// Rebuilds the session using the API key currently in config.
    private func restartSession() {
        guard let apiKey = SDKConfigStore.shared.current.apiKey, !apiKey.isEmpty else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Cannot rebuild forms session: SDK is not initialized.")
            }
            return
        }
        startSession(apiKey: apiKey)
    }

    private func endSession() {
        presenter.cancelDelayedPresentation()
        session = nil
    }

    // MARK: - App Lifecycle Observation

    private func startLifecycleObservation() {
        // Replacing an existing observation would leak the previous task.
        guard lifecycleObserver == nil else { return }

        let observer = LifecycleObserver()
        observer.startObserving()
        lifecycleObserver = observer

        lifecycleEventsTask = Task { [weak self] in
            for await event in observer.eventsStream {
                guard let self else { return }
                await handleAppLifecycleEvent(event)
            }
        }
    }

    /// Handles one app lifecycle transition. Non-throwing by construction, so a failure handling
    /// a single event can't break out of the `for await` loop and silently disable all future
    /// foreground/background handling.
    private func handleAppLifecycleEvent(_ event: LifecycleObserver.Event) async {
        switch event {
        case .foregrounded:
            await handleForegrounded()
        case .backgrounded:
            lastBackgrounded = Date()
            await session?.dispatchLifecycleEvent("background")
        }
    }

    private func handleForegrounded() async {
        await session?.dispatchLifecycleEvent("foreground")

        if lastBackgrounded != nil {
            if isSessionExpired {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info(
                        "App session has exceeded timeout duration; re-initializing IAF"
                    )
                }
                restartSession()
            }
        } else {
            // When opening Notification/Control Center, the system will not dispatch a `backgrounded` event,
            // but it will dispatch a `foregrounded` event when Notification/Control Center is dismissed.
            // This check ensures that we don't reinitialize in this situation.
            if session == nil {
                // fresh launch
                restartSession()
            }
        }
    }

    private var isSessionExpired: Bool {
        guard let lastBackgrounded,
              let timeoutDuration = configuration?.sessionTimeoutDuration
        else { return false }
        let timeElapsed = Date().timeIntervalSince(lastBackgrounded)
        return timeElapsed > timeoutDuration
    }

    // MARK: - Cleanup & Destruction

    func destroyWebviewAndListeners() {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("UnregisterFromInAppForms; destroying webview and listeners")
        }
        isInitializingOrInitialized = false

        lifecycleEventsTask?.cancel()
        lifecycleEventsTask = nil
        lifecycleObserver?.stopObserving()
        lifecycleObserver = nil
        lastBackgrounded = nil

        companyEventsTask?.cancel()
        companyEventsTask = nil
        companyObserver?.stopObserving()
        companyObserver = nil

        endSession()
    }
}
