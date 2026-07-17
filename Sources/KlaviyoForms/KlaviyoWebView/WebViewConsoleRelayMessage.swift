//
// WebViewConsoleRelayMessage.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
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
