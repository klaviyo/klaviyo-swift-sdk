//
//  ActionType.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

import Foundation

/// Represents the supported action types for push notification buttons.
public enum ActionType: String, Equatable {
    case openApp = "open_app"
    case deepLink = "deep_link"

    public func displayName() -> String {
        switch self {
        case .openApp: return "Open App"
        case .deepLink: return "Deep Link"
        }
    }
}
