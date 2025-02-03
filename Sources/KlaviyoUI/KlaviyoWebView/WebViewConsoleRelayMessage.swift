//
//  WebViewConsoleRelayMessage.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 1/27/25.
//

struct WebViewConsoleRelayMessage: Decodable {
    let level: Level
    let message: String

    enum Level: String, Decodable {
        case log
        case warn
        case error
    }
}
