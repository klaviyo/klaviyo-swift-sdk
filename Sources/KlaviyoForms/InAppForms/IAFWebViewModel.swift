//
//  IAFWebViewModel.swift
//  TestApp
//
//  Created by Andrew Balmer on 1/27/25.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog
import WebKit

class IAFWebViewModel {
    // MARK: - Properties

    let url: URL
    var loadScripts: Set<WKUserScript>? = Set<WKUserScript>()
    var messageHandlers: Set<String>? = Set(MessageHandler.allCases.map(\.rawValue))

    private let companyId: String?
    private let assetSource: String?

    // MARK: - Scripts

    private var klaviyoJsWKScript: WKUserScript? {
        var apiURL = environment.cdnURL()
        apiURL.path = "/onsite/js/klaviyo.js"
        apiURL.queryItems = [
            URLQueryItem(name: "company_id", value: companyId),
            URLQueryItem(name: "env", value: "in-app")
        ]

        if let assetSource {
            let assetSourceQueryItem = URLQueryItem(name: "assetSource", value: assetSource)
            apiURL.queryItems?.append(assetSourceQueryItem)
        }

        let klaviyoJsScript = """
            var script = document.createElement('script');
            script.id = 'klaviyoJS';
            script.type = 'text/javascript';
            script.src = '\(apiURL)';
            document.head.appendChild(script)
        """

        return WKUserScript(source: klaviyoJsScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private var sdkNameWKScript: WKUserScript {
        let sdkName = environment.sdkName()
        let sdkNameScript = "document.head.setAttribute('data-sdk-name', '\(sdkName)');"
        return WKUserScript(source: sdkNameScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private var sdkVersionWKScript: WKUserScript {
        let sdkVersion = environment.sdkVersion()
        let sdkVersionScript = "document.head.setAttribute('data-sdk-version', '\(sdkVersion)');"
        return WKUserScript(source: sdkVersionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private var handshakeWKScript: WKUserScript {
        let handshakeStringified = IAFNativeBridgeEvent.handshake
        let handshakeScript = "document.head.setAttribute('data-native-bridge-handshake', '\(handshakeStringified)');"
        return WKUserScript(source: handshakeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: - Initializer

    init(url: URL, companyId: String, assetSource: String? = nil) {
        self.url = url
        self.companyId = companyId
        self.assetSource = assetSource
        initializeLoadScripts()
    }

    func initializeLoadScripts() {
        guard let klaviyoJsWKScript else { return }
        loadScripts?.insert(klaviyoJsWKScript)
        loadScripts?.insert(sdkNameWKScript)
        loadScripts?.insert(sdkVersionWKScript)
        loadScripts?.insert(handshakeWKScript)
    }
}
