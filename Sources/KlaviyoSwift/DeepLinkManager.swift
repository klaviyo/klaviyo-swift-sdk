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
    /// Transient reentrancy guard — `true` while a deep link is being opened.
    /// Not persisted; reconstructed on launch.
    static var isProcessingDeepLink = false

    /// Opens `url` via the shared environment link handler, guarding against
    /// overlapping opens. If a deep link is already being processed this is a
    /// no-op (matching the reducer's "already processing" guard).
    ///
    /// The guard and its `true` assignment run synchronously before the
    /// `await`, so on the main actor overlapping calls are reliably skipped.
    ///
    /// The guard is process-wide: an open triggered from any entry point (push
    /// body tap, action button, tracking-link resolution, or the event
    /// dispatcher) suppresses a concurrent open from another.
    static func openDeepLink(_ url: URL) async {
        if let spy = openDeepLinkSpy {
            spy(url)
            return
        }
        guard !isProcessingDeepLink else {
            if #available(iOS 14.0, *) {
                Logger.navigation.log("Already processing a deep link; skipping.")
            }
            return
        }
        isProcessingDeepLink = true
        await environment.linkHandler.openURL(url)
        isProcessingDeepLink = false
    }
}

// MARK: - Test-only hooks

// TEST-ONLY. The members below exist solely so the reducer / facade test suites
// can observe deep-link invocations and restore state between tests.
extension DeepLinkManager {
    /// When non-nil, called by `openDeepLink(_:)` instead of the production path.
    /// Reset to nil after each test via `resetToProduction()`.
    static var openDeepLinkSpy: ((URL) -> Void)?

    /// Resets the spy and the transient processing flag.
    /// Call this in `setUp` and `tearDown` of any test that installs the spy.
    static func resetToProduction() {
        openDeepLinkSpy = nil
        isProcessingDeepLink = false
    }
}
