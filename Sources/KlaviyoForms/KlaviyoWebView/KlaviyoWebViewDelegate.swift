//
//  KlaviyoWebViewDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

import Combine
import Foundation
import WebKit

protocol KlaviyoWebViewDelegate: UIViewController {
    @MainActor
    func preloadUrl()

    @MainActor
    func evaluateJavaScript(_ script: String) async throws -> Any?
}
