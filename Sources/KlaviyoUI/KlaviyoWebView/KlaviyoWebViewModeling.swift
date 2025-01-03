//
//  KlaviyoWebViewModeling.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/1/24.
//

import Combine
import Foundation
import WebKit

protocol KlaviyoWebViewModeling {
    var url: URL { get }

    /// Scripts to be injected into the ``WKWebView`` when the website loads.
    var loadScripts: [String: WKUserScript]? { get }

    /// Streams scripts for the ``WKWebView`` to execute.
    var scriptStream: AsyncStream < (script: String, callback: (@Sendable (Result<Any?, Error>) -> Void)?)> { get }

    func handleNavigationEvent(_ event: WKNavigationEvent)
    @MainActor func handleScriptMessage(_ message: WKScriptMessage)
}
