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
package final class FormsPreviewTokenStore {
    package static let shared = FormsPreviewTokenStore()

    /// The format onsite-in-app-forms accepts for a preview token.
    private nonisolated static let tokenPattern = "^[A-Za-z0-9_-]{43}$"

    /// The current valid preview token, or `nil` when forms load normally. Publishes only
    /// when the value changes.
    @Published package private(set) var token: String?

    package init() {}

    /// Returns `token` without surrounding whitespace when it is a well-formed preview token,
    /// and `nil` when it is `nil`, empty or whitespace. A malformed token returns `nil` with a
    /// warning that omits its value.
    package nonisolated static func validate(_ token: String?) -> String? {
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

    /// Stores `token` after validation without touching the forms session. `nil`, empty or
    /// whitespace clears the token, and a malformed token is dropped with a warning, which also
    /// clears any previous token.
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

    /// Restarts the in-app forms session. KlaviyoForms sets this while forms are registered and
    /// clears it when they unregister, so it is `nil` whenever there is no session to restart.
    package var restartFormsSession: (@MainActor () -> Void)?

    /// Starts a forms preview session with `token`: stores it and, if forms are registered,
    /// restarts the session so a new webview loads the preview. Before forms register, the first
    /// session loads it instead. A malformed token changes nothing.
    /// - Returns: `true` when `token` was well formed and the preview started.
    @discardableResult
    package func startPreview(_ token: String) -> Bool {
        guard let validated = Self.validate(token) else { return false }
        setToken(validated)
        restartSession()
        return true
    }

    /// Ends the forms preview session: clears the token and, if forms are registered, restarts
    /// the session with published forms.
    package func endPreview() {
        clear()
        restartSession()
    }

    private func restartSession() {
        guard let restartFormsSession else {
            if #available(iOS 14.0, *) {
                Logger.formsPreview.info("Forms preview will start when forms register")
            }
            return
        }
        restartFormsSession()
    }
}
