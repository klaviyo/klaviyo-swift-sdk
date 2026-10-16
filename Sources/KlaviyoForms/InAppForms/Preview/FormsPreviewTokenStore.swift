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
@MainActor
final class FormsPreviewTokenStore {
    static let shared = FormsPreviewTokenStore()

    /// The format onsite-in-app-forms accepts for a preview token.
    private static let tokenPattern = "^[A-Za-z0-9_-]{43}$"

    /// The current valid preview token, or `nil` when forms load normally. Publishes only
    /// when the value changes.
    @Published private(set) var token: String?

    init() {}

    /// Returns `token` when it is a well-formed preview token, and `nil` when it is `nil`,
    /// empty or whitespace. A malformed token returns `nil` with a warning that omits its value.
    static func validate(_ token: String?) -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard token.range(of: tokenPattern, options: .regularExpression) != nil else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Ignoring malformed forms preview token")
            }
            return nil
        }
        return token
    }

    /// Stores `token` after validation. `nil`, empty or whitespace clears the token, and a
    /// malformed token is dropped with a warning, which also clears any previous token.
    func setToken(_ token: String?) {
        let validated = Self.validate(token)
        guard validated != self.token else { return }
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info(
                "Forms preview token \(validated == nil ? "cleared" : "set", privacy: .public)"
            )
        }
        self.token = validated
    }

    func clear() {
        setToken(nil)
    }

    /// Stores `configuration`'s preview token, if it has one. A configuration without a token
    /// leaves the current token unchanged. A loaded page receives a new token over the bridge.
    func apply(_ configuration: InAppFormsConfig) {
        guard let previewToken = configuration.previewToken, !previewToken.isEmpty else { return }
        setToken(previewToken)
    }
}
