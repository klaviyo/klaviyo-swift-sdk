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

    /// Publishes scripts for the ``WKWebView`` to execute.
    var scriptSubject: PassthroughSubject<(script: String, callback: ((Result<Any?, Error>) -> Void)?), Never> { get }

    func handleNavigationEvent(_ event: WKNavigationEvent)
    func handleScriptMessage(_ message: WKScriptMessage)
}
