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

    private let url: URL

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()

        webView = createWebView()

        view.addSubview(webView)

        configureSubviewConstraints()
    }

    override func viewDidLoad() {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func createWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        // customize any WKWebViewConfiguration properties here
        // ex: config.allowsInlineMediaPlayback = true
        return config
    }

    func createWebView() -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: config)
        // customize any WKWebView behaviors here
        // ex: webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func configureSubviewConstraints() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        webView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }
}

// MARK: - Previews

@available(iOS 17.0, *)
#Preview("Klaviyo.com") {
    KlaviyoWebViewController(url: URL(string: "https://www.klaviyo.com")!)
}