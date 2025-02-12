//
//  MockWKScriptMessage.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/12/25.
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
