//
//  KlaviyoWebViewOverlayManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 1/15/25.
//

import KlaviyoCore
import SwiftUI
import UIKit

class KlaviyoWebViewOverlayManager {
    @MainActor public static let shared = KlaviyoWebViewOverlayManager()
    private var isLoading: Bool = false

    /// Presents a view controller on the top-most view controller
    /// - Parameters:
    ///   - viewController: A `UIViewController` instance to present.
    ///   - modalPresentationStyle: The modal presentation style to use (default is `.overCurrentContext`).
    ///
    /// - warning: For internal use only. The host app should not manually call this method, as
    /// the logic for fetching and displaying forms will be handled internally within the SDK.
    @MainActor func preloadAndShow(
        viewModel: KlaviyoWebViewModeling,
        modalPresentationStyle: UIModalPresentationStyle = .overCurrentContext) {
        guard !isLoading else {
            return
        }

        isLoading = true

        let viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController.modalPresentationStyle = modalPresentationStyle

        Task {
            defer { isLoading = false }

            try await viewModel.preloadWebsite(timeout: NetworkSession.networkTimeout)

            guard let topController = UIApplication.shared.topMostViewController else {
                return
            }
            topController.present(viewController, animated: false, completion: nil)
        }
    }
}
