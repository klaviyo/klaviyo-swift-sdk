//
//  KlaviyoWebViewModeling.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/1/24.
//

import Combine
import Foundation
import WebKit

@_spi(KlaviyoPrivate)
public protocol KlaviyoWebViewModeling: AnyObject {
    var url: URL { get }
    var delegate: KlaviyoWebViewDelegate? { get set }

    /// Scripts to be injected into the ``WKWebView`` when the website loads.
    var loadScripts: [String: WKUserScript]? { get }

    func preloadWebsite(timeout: UInt64) async throws
    func handleNavigationEvent(_ event: WKNavigationEvent)
    func handleScriptMessage(_ message: WKScriptMessage)
}
