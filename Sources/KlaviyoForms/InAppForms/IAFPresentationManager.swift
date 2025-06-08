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

    private var isLoading: Bool = false
    private var formEventTask: Task<Void, Never>?

    lazy var indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            return nil
        }
    }()

    private init() {}

    #if DEBUG
    package init(viewController: KlaviyoWebViewController?) {
        self.viewController = viewController
    }
    #endif

    func setupLifecycleEvents(configuration: IAFConfiguration) {
        lifecycleCancellable = environment.appLifeCycle.lifeCycleEvents()
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
                                    self.constructWebview()
                                }
                            })
                        } else {
                            // launching
                            try await self.handleLifecycleEvent("foreground", additionalAction: {
                                self.constructWebview()
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

        setupApiKeyPublisher()
    }

    private func setupApiKeyPublisher() {
        apiKeyCancellable = KlaviyoInternal.apiKeyPublisher()
            .scan((nil, false)) { previous, current in
                (current, previous.0 != nil)
            }
            .sink { [weak self] _, isSubsequent in
                Task { @MainActor in
                    if isSubsequent {
                        // subsequent API key changes
                        self?.destroyWebView()
                        self?.constructWebview()
                    } else {
                        // initial launch
                        self?.constructWebview()
                    }
                }
            }
    }

    func constructWebview(assetSource: String? = nil) {
        guard !isLoading else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("In-App Form is already loading; ignoring request.")
            }
            return
        }

        guard let fileUrl = indexHtmlFileUrl else { return }

        isLoading = true

        Task {
            defer { isLoading = false }

            guard let companyId = await withCheckedContinuation({ continuation in
                KlaviyoInternal.apiKey { apiKey in
                    continuation.resume(returning: apiKey)
                }
            }) else {
                environment.emitDeveloperWarning("SDK must be initialized before usage.")
                return
            }

            let viewModel = IAFWebViewModel(url: fileUrl, companyId: companyId, assetSource: assetSource)
            viewController = KlaviyoWebViewController(viewModel: viewModel)
            viewController?.modalPresentationStyle = .overCurrentContext

            // establish the handshake with KlaviyoJS
            do {
                try await viewModel.establishHandshake(timeout: NetworkSession.networkTimeout.seconds)
            } catch {
                if #available(iOS 14.0, *) { Logger.webViewLogger.warning("Unable to establish handshake with KlaviyoJS: \(error).") }
                viewController = nil
                return
            }

            // now that we've established the handshake, we can start a task that listens for Form events.
            formEventTask = Task {
                for await event in viewModel.formLifecycleStream {
                    handleFormEvent(event)
                }
            }
        }
    }

    // MARK: - Event Handling

    func handleLifecycleEvent(_ event: String, additionalAction: (() async -> Void)? = nil) async throws {
        do {
            let result = try await viewController?.evaluateJavaScript("dispatchLifecycleEvent('\(event)')")
            if let successMessage = result as? String {
                print("Successfully evaluated Javascript; message: \(successMessage)")
            }
            if let additionalAction = additionalAction {
                await additionalAction()
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
            formEventTask?.cancel()
        }
    }

    // MARK: - Object lifecycle

    func destroyWebView() {
        guard let viewController else { return }
        viewController.dismiss(animated: false) { [weak self] in
            self?.viewController = nil
        }
    }

    func destroyWebviewAndListeners() {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("UnregisterFromInAppForms; destroying webview and listeners")
        }
        isLoading = false
        lastBackgrounded = nil
        lifecycleCancellable?.cancel()
        apiKeyCancellable?.cancel()
        formEventTask?.cancel()
        lifecycleCancellable = nil
        apiKeyCancellable = nil
        formEventTask = nil
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
