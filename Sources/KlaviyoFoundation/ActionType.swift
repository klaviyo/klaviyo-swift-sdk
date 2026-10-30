//
//  ActionType.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Represents the supported action types for push notification buttons.
package enum ActionType: String, Equatable {
    case openApp = "open_app"
    case deepLink = "deep_link"
    case openUrl = "open_url"

    package func displayName() -> String {
        switch self {
        case .openApp: return "Open App"
        case .deepLink: return "Deep Link"
        case .openUrl: return "Open URL"
        }
    }
}
