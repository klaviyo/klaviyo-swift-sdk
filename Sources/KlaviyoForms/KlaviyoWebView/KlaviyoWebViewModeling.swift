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

    /// When non-`nil`, ``url``'s contents are loaded as an HTML string with this as the document
    /// base URL, giving the document a same-origin web origin (avoiding `Origin: null`). When
    /// `nil`, ``url`` is loaded directly.
    var baseURL: URL? { get }

    var delegate: KlaviyoWebViewDelegate? { get set }

    /// Scripts & message handlers to be injected into the ``WKWebView`` when the website loads.
    var loadScripts: Set<WKUserScript>? { get }
    var messageHandlers: Set<String>? { get }

    @MainActor
    func handleNavigationEvent(_ event: WKNavigationEvent)

    @MainActor
    func handleScriptMessage(_ message: WKScriptMessage)
}

extension KlaviyoWebViewModeling {
    /// Default: no base URL; ``url`` is loaded directly. Override to load same-origin.
    var baseURL: URL? {
        nil
    }
}
