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

class IAFPresentationManager {
    @MainActor static let shared = IAFPresentationManager()

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

    @MainActor
    func presentIAF(assetSource: String? = nil) {
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
                await environment.emitDeveloperWarning("SDK must be initialized before usage.")
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

    @MainActor
    private func handleFormEvent(_ event: IAFLifecycleEvent) {
        switch event {
        case .present:
            presentForm()
        case .dismiss:
            dismissForm()
            formEventTask?.cancel()
        case .abort:
            formEventTask?.cancel()
        }
    }

    @MainActor
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
            dismissForm()
        } else {
            topController.present(viewController, animated: false, completion: nil)
        }
    }

    @MainActor
    private func dismissForm() {
        viewController?.dismiss(animated: false) { [weak self] in
            self?.viewController = nil
        }
    }
}

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
