//
//  ActionType.swift
//

// NOTE: KlaviyoCore carries the authoritative copy of this enum
// (Sources/KlaviyoCore/Models/ActionType.swift). This internal copy exists
// because KlaviyoSwiftExtension cannot depend on KlaviyoCore (NSE/share-extension
// sandbox restriction). The two copies are intentionally kept in sync. If you
// add or rename cases here, mirror the change there.

import Foundation

/// Represents the supported action types for push notification buttons.
enum ActionType: String, Equatable {
    case openApp = "open_app"
    case deepLink = "deep_link"
}
