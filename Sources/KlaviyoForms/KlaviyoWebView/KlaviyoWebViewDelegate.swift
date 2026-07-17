//
// KlaviyoWebViewDelegate.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
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
