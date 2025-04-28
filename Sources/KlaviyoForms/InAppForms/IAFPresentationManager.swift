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

class IAFPresentationManager {
    static let shared = IAFPresentationManager()
    private var lifecycleCancellable: AnyCancellable?

    lazy var indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            return nil
        }
    }()

    private var isLoading: Bool = false

    func setupLifecycleEvents() {
        lifecycleCancellable = AppLifeCycleEvents.production.lifeCycleEvents()
            .sink { [weak self] event in
                switch event {
                // TODO: Implement app session here based on these lifecycle events
                case .terminated:
                    print("[KlaviyoForms] terminated")
                case .foregrounded:
                    print("[KlaviyoForms] foregrounded")
                case .backgrounded:
                    print("[KlaviyoForms] backgrounded")
                case let .reachabilityChanged(status: status):
                    print("[KlaviyoForms] reachabilityChanged: \(status)")
                }
            }
    }

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
                environment.emitDeveloperWarning("SDK must be initialized before usage.")
                return
            }

            let viewModel = IAFWebViewModel(url: fileUrl, companyId: companyId, assetSource: assetSource)
            let viewController = KlaviyoWebViewController(viewModel: viewModel)
            viewController.modalPresentationStyle = .overCurrentContext

            do {
                try await viewModel.preloadWebsite(timeout: NetworkSession.networkTimeout)
            } catch {
                viewController.dismiss()
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Error preloading In-App Form: \(error).")
                }
                return
            }

            guard let topController = UIApplication.shared.topMostViewController else {
                viewController.dismiss()
                return
            }

            if topController.isKlaviyoVC || topController.hasKlaviyoVCInStack {
                viewController.dismiss()
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("In-App Form is already being presented; ignoring request")
                }
            } else {
                topController.present(viewController, animated: false, completion: nil)
            }
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
