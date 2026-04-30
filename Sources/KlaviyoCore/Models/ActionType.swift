//
//  ActionType.swift
//
//
//  Created by Belle Lim on 1/20/26.
//

// NOTE: KlaviyoSwiftExtension carries an internal copy of this enum
// (Sources/KlaviyoSwiftExtension/ActionType.swift) because that target cannot
// depend on KlaviyoCore (NSE/share-extension sandbox restriction). The two
// copies are intentionally kept in sync. If you add or rename cases here,
// mirror the change there.

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
