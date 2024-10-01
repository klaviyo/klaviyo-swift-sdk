//
//  KlaviyoWebViewModel.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

import Foundation
import WebKit

class KlaviyoWebViewModel {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    // MARK: handle WKWebView events

    func handleNavigationEvent(_ event: WKNavigationEvent) {
        // TODO: handle navigation events
    }

    func handleScriptMessage(_ message: WKScriptMessage) {
        // TODO: handle script message
    }
}
