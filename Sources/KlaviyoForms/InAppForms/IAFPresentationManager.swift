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
    private var isLoading: Bool = false

    @MainActor
    func presentIAF(assetSource: String? = nil) {
        guard !isLoading else { return }
        guard let fileUrl = indexHtmlFileUrl else { return }

        isLoading = true
        Task {
            defer { isLoading = false }

            guard let companyId = await getCompanyID() else {
                return
            }

            let viewModel = IAFWebViewModel(url: fileUrl, companyId: companyId, assetSource: assetSource)
            let viewController = KlaviyoWebViewController(viewModel: viewModel)

            do {
                try await viewController.preloadWebsite(timeout: NetworkSession.networkTimeout)

                if let topController = UIApplication.shared.topMostViewController,
                   topController.shouldPresentIAF {
                    viewController.modalPresentationStyle = .overCurrentContext
                    topController.present(viewController, animated: true, completion: nil)
                }
            }
        }
    }

    private func getCompanyID() async -> String? {
        guard let companyId = await withCheckedContinuation({ continuation in
            KlaviyoInternal.apiKey { apiKey in
                continuation.resume(returning: apiKey)
            }
        }) else {
            environment.emitDeveloperWarning("SDK must be initialized before usage.")
            return nil
        }

        return companyId
    }

    private lazy var indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            return nil
        }
    }()
}

extension UIViewController {
    fileprivate var shouldPresentIAF: Bool {
        !isKlaviyoVC && !hasKlaviyoVCInStack
    }

    private var isKlaviyoVC: Bool {
        self is KlaviyoWebViewController
    }

    private var hasKlaviyoVCInStack: Bool {
        guard let navigationController = navigationController else {
            return false
        }
        return navigationController.viewControllers.contains(where: \.isKlaviyoVC)
    }
}
