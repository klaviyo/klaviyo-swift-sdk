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
    static let shared = IAFPresentationManager()
    private var viewController: KlaviyoWebViewController?

    lazy var indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            return nil
        }
    }()

    private var isLoading: Bool = false
    private var formWillAppearTask: Task<Void, Never>?

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
            viewController = KlaviyoWebViewController(viewModel: viewModel)
            viewController?.modalPresentationStyle = .overCurrentContext

            await viewModel.loadIAFTemplate()

            // listen for formwillappear
            formWillAppearTask = Task {
                for await _ in viewModel.formWillAppearStream {
                    handleFormWillAppear()
                }
            }
        }
    }

    @MainActor
    private func handleFormWillAppear() {
        guard let viewController else { return }

        guard let topController = UIApplication.shared.topMostViewController else {
            viewController.dismiss(animated: false)
            return
        }

        if topController.isKlaviyoVC || topController.hasKlaviyoVCInStack { // FIXME: use viewController.isBeingPresented here?
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("In-App Form is already being presented; ignoring formWillAppear message")
            }
        } else {
            topController.present(viewController, animated: false, completion: nil)
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
