//
// MockWKScriptMessage.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import WebKit

class MockWKScriptMessage: WKScriptMessage {
    private let mockName: String
    private let mockBody: Any

    init(name: String, body: Any) {
        mockName = name
        mockBody = body
        super.init() // Calling the superclass initializer
    }

    override var name: String {
        mockName
    }

    override var body: Any {
        mockBody
    }
}
