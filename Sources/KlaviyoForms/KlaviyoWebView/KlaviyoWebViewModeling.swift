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

    /// Scripts & message handlers to be injected into the ``WKWebView`` when the website loads.
    var loadScripts: Set<WKUserScript>? { get }
    var messageHandlers: Set<String>? { get }

    @MainActor
    func handleNavigationEvent(_ event: WKNavigationEvent)

    @MainActor
    func handleScriptMessage(_ message: WKScriptMessage)
}
