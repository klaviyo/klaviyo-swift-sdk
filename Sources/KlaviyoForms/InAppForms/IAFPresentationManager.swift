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

    var cancellables: Set<AnyCancellable> = []

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

            let companyId = try await self.loadAPIKey()

            let viewModel = IAFWebViewModel(url: fileUrl, companyId: companyId, assetSource: assetSource)
            let viewController = KlaviyoWebViewController(viewModel: viewModel)
            viewController.modalPresentationStyle = .overCurrentContext

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

    func loadAPIKey() async throws -> String {
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    let cancellable = KlaviyoInternal.apiKey().sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .finished:
                                break
                            case let .failure(error):
                                continuation.resume(throwing: error)
                            }
                        },
                        receiveValue: { value in
                            continuation.resume(returning: value)
                        })
                    cancellables.insert(cancellable)
                }
            },
            onCancel: {
                // Handle cancellation here
                for cancellable in cancellables {
                    cancellable.cancel()
                }
                cancellables.removeAll()
            })
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
