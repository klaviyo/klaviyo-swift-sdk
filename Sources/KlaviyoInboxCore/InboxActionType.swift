//
//  InboxActionType.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

// NOTE: `KlaviyoCore.ActionType` and `openUrlAllowedSchemes` are the authoritative copies, and
// `KlaviyoSwiftExtension` holds another. This module cannot depend on either (extension-safe), so it
// carries its own. MAGE-1372 consolidates them; `InboxActionTypeParityTests` fails if they drift.

import Foundation

/// The button action types this SDK version understands.
package enum InboxActionType: String, CaseIterable {
    case openApp = "open_app"
    case deepLink = "deep_link"
    case openUrl = "open_url"
}

/// URL schemes allowed for an `open_url` destination.
///
/// `smsto` is intentionally absent: iOS Messages only registers `sms:`.
package enum InboxURLSchemeAllowlist {
    package static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms"]

    package static func isAllowed(_ url: URL) -> Bool {
        url.scheme.map { allowedSchemes.contains($0.lowercased()) } ?? false
    }
}
