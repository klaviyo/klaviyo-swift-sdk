//
//  URLSchemeAllowlist.swift
//  klaviyo-swift-sdk
//

// NOTE: KlaviyoCore carries the authoritative copy of this constant
// (Sources/KlaviyoCore/Utils/URLSchemeAllowlist.swift). This internal copy exists
// because KlaviyoSwiftExtension cannot depend on KlaviyoCore (NSE/share-extension
// sandbox restriction). The two copies are intentionally kept in sync. If you
// change the set here, mirror the change there.

import Foundation

/// URL schemes allowed for the `open_url` push action.
///
/// These schemes are safe to hand off to `UIApplication.shared.open(_:)` directly.
/// Schemes **not** on this list (e.g. `intent:`, `javascript:`, `file:`, `geo:`)
/// are silently dropped.
let openUrlAllowedSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms", "smsto"]
