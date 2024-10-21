//
//  KlaviyoWebViewContainer.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/21/24.
//

import SwiftUI

public struct KlaviyoWebViewContainer: UIViewControllerRepresentable {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIViewController(context: Context) -> KlaviyoWebWrapperViewController {
        let viewModel = KlaviyoWebViewModel(url: url)
        let viewController = KlaviyoWebWrapperViewController(viewModel: viewModel)
        return viewController
    }

    public func updateUIViewController(_ uiViewController: KlaviyoWebWrapperViewController, context: Context) {}
}

// MARK: - Previews

#if swift(>=5.9)
@available(iOS 17.0, *)
#Preview("Klaviyo.com") {
    let url = URL(string: "https://www.klaviyo.com")!
    KlaviyoWebViewContainer(url: url)
}
#endif
