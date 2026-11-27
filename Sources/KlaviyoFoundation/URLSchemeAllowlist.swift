//
//  URLSchemeAllowlist.swift
//  klaviyo-swift-sdk
//

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

package extension URL {
    /// True if this URL's scheme is in ``openUrlAllowedSchemes``. Shared so the `open_url`
    /// gate on push action buttons and `web_url` can never diverge from each other.
    var hasAllowedOpenUrlScheme: Bool {
        scheme.map { openUrlAllowedSchemes.contains($0.lowercased()) } ?? false
    }
}
