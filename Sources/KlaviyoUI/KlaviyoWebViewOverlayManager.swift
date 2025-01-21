//
//  KlaviyoWebViewOverlayManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 1/15/25.
//

import SwiftUI
import UIKit

@_spi(KlaviyoPrivate)
public class KlaviyoWebViewOverlayManager {
    public static let shared = KlaviyoWebViewOverlayManager()
    private var isLoading: Bool = false

    /// Presents a view controller on the top-most view controller
    /// - Parameters:
    ///   - viewController: A `UIViewController` instance to present.
    ///   - modalPresentationStyle: The modal presentation style to use (default is `.overCurrentContext`).
    ///
    /// - warning: For internal use only. The host app should not manually call this method, as
    /// the logic for fetching and displaying forms will be handled internally within the SDK.
    @_spi(KlaviyoPrivate)
    @MainActor public func preloadAndShow(
        viewModel: KlaviyoWebViewModeling,
        modalPresentationStyle: UIModalPresentationStyle = .overCurrentContext) {
        guard !isLoading else {
            return
        }

        guard let topController = UIApplication.shared.topMostViewController else {
            return
        }

        isLoading = true

        let viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController.modalPresentationStyle = modalPresentationStyle

        Task {
            defer { isLoading = false }

            try await viewModel.preloadWebsite(timeout: 8_000_000_000)
            topController.present(viewController, animated: true, completion: nil)
        }
    }
}
