//
//  KlaviyoWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

import Combine
import Foundation
import WebKit

class KlaviyoWebViewModel {
    let url: URL
    let loadScripts: [String: WKUserScript]

    /// Publishes scripts for the `WKWebView` to execute.
    let scriptSubject = PassthroughSubject<(script: String, callback: ((Result<Any?, Error>) -> Void)?), Never>()

    init(url: URL) {
        self.url = url
        loadScripts = KlaviyoWebViewModel.initializeLoadScripts()
    }

    private static func initializeLoadScripts() -> [String: WKUserScript] {
        var scripts: [String: WKUserScript] = [:]

        // TODO: initialize scripts

        return scripts
    }

    // MARK: handle WKWebView events

    func handleNavigationEvent(_ event: WKNavigationEvent) {
        // TODO: handle navigation events
    }

    func handleScriptMessage(_ message: WKScriptMessage) {
        // TODO: handle script message
    }
}
