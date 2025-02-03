//
//  IafPresentationManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/3/25.
//

import Foundation
import OSLog
import UIKit

@_spi(KlaviyoPrivate)
public class IafPresentationManager {
    @_spi(KlaviyoPrivate)
    public static let shared = IafPresentationManager()

    lazy var indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            return nil
        }
    }()

    private var isLoading: Bool = false

    @_spi(KlaviyoPrivate)
    @MainActor public func presentIaf() {
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

        let viewModel = IafWebViewModel(url: fileUrl)
        let viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController.modalPresentationStyle = .overCurrentContext

        Task {
            defer { isLoading = false }

            try await viewModel.preloadWebsite(timeout: 8_000_000_000)

            guard let topController = UIApplication.shared.topMostViewController else {
                return
            }
            topController.present(viewController, animated: true, completion: nil)
        }
    }
}
