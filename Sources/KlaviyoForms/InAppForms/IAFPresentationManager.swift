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

    lazy var indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            return nil
        }
    }()

    private var isLoading: Bool = false

    @MainActor
    func presentIAF(assetSource: String? = nil) {
        // createstatepublisher and subscribe
        let companyId = KlaviyoInternal.apiKey { companyId in
            guard let companyId else { return }
            self.wipstuff(companyId: companyId, assetSource: assetSource)
        }
        //            environment.emitDeveloperWarning("SDK must be initialized before usage.")
        //            if #available(iOS 14.0, *) {
        //                Logger.webViewLogger.warning("Unable to initialize KlaviyoJS script on In-App Form HTML due to missing API key.")
        //            }
        //            return
    }

    func wipstuff(companyId: String, assetSource: String?) {
        guard !isLoading else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("In-App Form is already loading; ignoring request.")
            }
            return
        }

        guard let fileUrl = indexHtmlFileUrl else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("URL for local HTML file is nil; unable to present In-App Form.")
            }
            return
        }

        isLoading = true

        let viewModel = IAFWebViewModel(url: fileUrl, companyId: companyId, assetSource: assetSource)
        let viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController.modalPresentationStyle = .overCurrentContext

        Task {
            defer { isLoading = false }

            do {
                try await viewModel.preloadWebsite(timeout: NetworkSession.networkTimeout)
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("Error preloading In-App Form: \(error).")
                }
                return
            }

            guard let topController = UIApplication.shared.topMostViewController else {
                return
            }

            if topController.isKlaviyoVC || topController.hasKlaviyoVCInStack {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("In-App Form is already being presented; ignoring request")
                }
            } else {
                topController.present(viewController, animated: true, completion: nil)
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
