//
// KlaviyoWebViewModeling.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Combine
import Foundation
import OSLog
import WebKit

protocol KlaviyoWebViewModeling: AnyObject {
    var url: URL { get }
    var delegate: KlaviyoWebViewDelegate? { get set }

    /// Scripts & message handlers to be injected into the ``WKWebView`` when the website loads.
    var loadScripts: Set<WKUserScript>? { get }
    var messageHandlers: Set<String>? { get }

    @MainActor
    func handleNavigationEvent(_ event: WKNavigationEvent)

    @MainActor
    func handleScriptMessage(_ message: WKScriptMessage)
}
