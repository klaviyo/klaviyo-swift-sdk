//
//  FormsPreviewTokenStore.swift
//  klaviyo-swift-sdk
//

import Combine
import Foundation
import OSLog

/// Holds the forms preview token in memory only. The token is a short-lived credential that
/// makes onsite-in-app-forms load draft forms instead of published forms. It is never
/// persisted and never logged.
///
/// Lives in KlaviyoCore so both KlaviyoForms (which reads it and writes it from its public API)
/// and KlaviyoSwift (which writes it when a preview push is opened) share one store.
@MainActor
package final class FormsPreviewTokenStore {
    package static let shared = FormsPreviewTokenStore()

    /// The format onsite-in-app-forms accepts for a preview token.
    private static let tokenPattern = "^[A-Za-z0-9_-]{43}$"

    /// The current valid preview token, or `nil` when forms load normally. Publishes only
    /// when the value changes.
    @Published package private(set) var token: String?

    /// Tokens whose preview onsite reported as ended or expired, kept so a configuration that
    /// still holds one cannot revive it. Tokens are short-lived, so this stays small.
    private var endedTokens: Set<String> = []

    package init() {}

    /// Returns `token` without surrounding whitespace when it is a well-formed preview token,
    /// and `nil` when it is `nil`, empty or whitespace. A malformed token returns `nil` with a
    /// warning that omits its value.
    package static func validate(_ token: String?) -> String? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        guard token.range(of: tokenPattern, options: .regularExpression) != nil else {
            if #available(iOS 14.0, *) {
                Logger.formsPreview.warning("Ignoring malformed forms preview token")
            }
            return nil
        }
        return token
    }

    /// Stores `token` after validation. `nil`, empty or whitespace clears the token, and a
    /// malformed token is dropped with a warning, which also clears any previous token.
    package func setToken(_ token: String?) {
        let validated = Self.validate(token)
        guard validated != self.token else { return }
        if #available(iOS 14.0, *) {
            Logger.formsPreview.info(
                "Forms preview token \(validated == nil ? "cleared" : "set", privacy: .public)"
            )
        }
        self.token = validated
    }

    package func clear() {
        setToken(nil)
    }

    /// Clears the stored token because its preview ended, and remembers it as ended.
    package func end() {
        if let token {
            endedTokens.insert(token)
        }
        clear()
    }

    /// Stores a token from an In-App Forms configuration. `nil` or empty leaves the current
    /// token unchanged, a malformed token clears it like the setter, and a token whose preview
    /// already ended is ignored. A loaded page receives a new token over the bridge.
    package func applyConfigurationToken(_ token: String?) {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let validated = Self.validate(token), endedTokens.contains(validated) {
            if #available(iOS 14.0, *) {
                Logger.formsPreview.info("Ignoring configured forms preview token; its preview already ended")
            }
            return
        }
        setToken(token)
    }
}
