//
//  KlaviyoWebViewModeling.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/1/24.
//

import Combine
import Foundation
import OSLog
import WebKit

protocol KlaviyoWebViewModeling: AnyObject {
    var url: URL { get }
    var delegate: KlaviyoWebViewDelegate? { get set }

    /// Pre-built HTML content with all data attributes embedded. When provided, the web view
    /// loads this string (with `url`'s directory as the base URL) instead of loading `url` directly.
    /// This ensures data attributes like the native bridge handshake are present in the initial HTML
    /// before any scripts execute.
    var htmlContent: String? { get }

    /// Scripts & message handlers to be injected into the ``WKWebView`` when the website loads.
    var loadScripts: Set<WKUserScript>? { get }
    var messageHandlers: Set<String>? { get }

    @MainActor
    func handleNavigationEvent(_ event: WKNavigationEvent)

    @MainActor
    func handleScriptMessage(_ message: WKScriptMessage)
}

extension KlaviyoWebViewModeling {
    var htmlContent: String? { nil }
}
