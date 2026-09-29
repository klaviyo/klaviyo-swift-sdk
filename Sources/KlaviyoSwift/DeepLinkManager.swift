//
//  DeepLinkManager.swift
//
//  Klaviyo Swift SDK
//
//  Created by Belle Lim on 7/16/26.
//

import Foundation
import KlaviyoCore
import OSLog

@MainActor
enum DeepLinkManager {
    /// Opens `url` via the shared environment link handler, routing to the host
    /// app's registered deep link handler when one exists. Like
    /// ``openExternalURL(_:)``, this has no reentrancy guard: `DeepLinkManager`
    /// is main-actor isolated, so there is no data race to prevent, and
    /// delivering two deep links in a row is harmless. Hosts already have to
    /// tolerate that, because iOS itself redelivers universal links through
    /// paths this SDK does not sit on.
    static func openDeepLink(_ url: URL) async {
        if let spy = openDeepLinkSpy {
            spy(url)
            return
        }
        await environment.linkHandler.openURL(url)
    }

    /// Opens an external web/system URL via the shared environment link handler,
    /// bypassing any registered custom deep link handler. Used by the `open_url`
    /// push action where the customer explicitly chose to open a URL in the
    /// system browser rather than route into the app. Concurrent external opens
    /// are harmless, so there is no reentrancy guard.
    static func openExternalURL(_ url: URL) async {
        if let spy = openExternalURLSpy {
            spy(url)
            return
        }
        await environment.linkHandler.openExternalURL(url)
    }
}

// MARK: - Test-only hooks

// TEST-ONLY. The members below exist solely so the reducer / facade test suites
// can observe deep-link invocations and restore state between tests.
extension DeepLinkManager {
    /// When non-nil, called by `openDeepLink(_:)` instead of the production path.
    /// Reset to nil after each test via `resetToProduction()`.
    static var openDeepLinkSpy: ((URL) -> Void)?

    /// When non-nil, called by `openExternalURL(_:)` instead of the production path.
    /// Reset to nil after each test via `resetToProduction()`.
    static var openExternalURLSpy: ((URL) -> Void)?

    /// Resets the spies.
    /// Call this in `setUp` and `tearDown` of any test that installs a spy.
    static func resetToProduction() {
        openDeepLinkSpy = nil
        openExternalURLSpy = nil
    }
}
