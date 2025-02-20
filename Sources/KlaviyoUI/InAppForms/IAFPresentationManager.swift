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
    func presentIAF() {
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

        let viewModel = IAFWebViewModel(url: fileUrl)
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

            guard !(topController is KlaviyoWebViewController) else {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("In-App Form is already presenting.")
                }
                return
            }
            topController.present(viewController, animated: true, completion: nil)
        }
    }
}
