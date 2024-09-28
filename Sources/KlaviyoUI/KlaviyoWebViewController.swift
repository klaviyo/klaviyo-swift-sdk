//
//  KlaviyoWebViewController.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/28/24.
//

import UIKit
import WebKit

class KlaviyoWebViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!

    override func loadView() {
        super.loadView()

        webView = createWebView()

        view.addSubview(webView)
    }

    func createWebView() -> WKWebView {
        let webView = WKWebView()
        // customize any WKWebView behaviors here
        // ex: webView.allowsBackForwardNavigationGestures = true
        return webView
    }
}
