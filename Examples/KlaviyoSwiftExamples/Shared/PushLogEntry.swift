//
// PushLogEntry.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation

/// A single push notification captured for display in the example app's Push Log screen.
struct PushLogEntry: Identifiable, Codable, Equatable {
    enum Source: String, Codable {
        case foreground = "Foreground"
        case background = "Background"
        case tapped = "Tapped"
    }

    let id: UUID
    let receivedAt: Date
    let source: Source
    let title: String
    let body: String
    let customData: [String: String]

    init(source: Source, title: String, body: String, customData: [String: String]) {
        id = UUID()
        receivedAt = Date()
        self.source = source
        self.title = title
        self.body = body
        self.customData = customData
    }
}
