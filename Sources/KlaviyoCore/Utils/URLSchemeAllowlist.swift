//
//  URLSchemeAllowlist.swift
//  klaviyo-swift-sdk
//

// NOTE: KlaviyoSwiftExtension carries an internal copy of this constant
// (Sources/KlaviyoSwiftExtension/URLSchemeAllowlist.swift) because that target cannot
// depend on KlaviyoCore (NSE/share-extension sandbox restriction). The two
// copies are intentionally kept in sync. If you change the set here, mirror
// the change there.

import Foundation

/// URL schemes allowed for the `open_url` push action.
///
/// These schemes are safe to hand off to `UIApplication.shared.open(_:)` directly.
/// Schemes **not** on this list (e.g. `intent:`, `javascript:`, `file:`, `geo:`)
/// are silently dropped.
///
/// Note: `smsto:` is intentionally excluded (unlike the Android SDK). iOS Messages only
/// registers `sms:`; `smsto:` has no iOS handler, so `UIApplication.shared.open(_:)` would
/// no-op. Use `sms:` for SMS on iOS.
package let openUrlAllowedSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms"]
