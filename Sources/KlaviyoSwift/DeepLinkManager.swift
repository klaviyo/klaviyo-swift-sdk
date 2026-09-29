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

    private static let defaultProcessingGuardTimeout: TimeInterval = 5

    /// Upper bound, in seconds, on how long ``isProcessingDeepLink`` stays
    /// latched while waiting on the host application's deep link handler.
    /// Overridden by tests; reset by ``resetToProduction()``.
    static var processingGuardTimeout: TimeInterval = defaultProcessingGuardTimeout

    /// Opens `url` via the shared environment link handler, guarding against
    /// overlapping opens. If a deep link is already being processed this is a
    /// no-op (matching the reducer's "already processing" guard).
    ///
    /// The guard and its `true` assignment run synchronously before the
    /// `await`, so on the main actor overlapping calls are reliably skipped.
    ///
    /// The guard is released when the open finishes or after
    /// ``processingGuardTimeout``, whichever comes first, so a host handler that
    /// never returns cannot block every later deep link.
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

        // A host handler that never returns must not latch the guard for the rest
        // of the process, which would silently drop every later deep link. `defer`
        // cannot cover that case on its own, because nothing unwinds when a call
        // simply never completes. The watchdog releases the guard instead.
        // ponytail: fixed window, and it cannot recover a handler that blocks the
        // main actor outright. Make the window injectable if a customer needs more.
        let watchdog = Task { @MainActor in
            let nanoseconds = UInt64(processingGuardTimeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            if #available(iOS 14.0, *) {
                Logger.navigation.error("""
                Deep link handler did not return in time; releasing the processing \
                guard so that later deep links are not dropped.
                """)
            }
            isProcessingDeepLink = false
        }
        defer {
            watchdog.cancel()
            isProcessingDeepLink = false
        }

        await environment.linkHandler.openURL(url)
    }

    /// Opens an external web/system URL via the shared environment link handler,
    /// bypassing any registered custom deep link handler. Used by the `open_url`
    /// push action where the customer explicitly chose to open a URL in the
    /// system browser rather than route into the app. Unlike `openDeepLink`,
    /// this has no reentrancy guard — concurrent external opens are harmless.
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

    /// Resets the spies and the transient processing flag.
    /// Call this in `setUp` and `tearDown` of any test that installs a spy.
    static func resetToProduction() {
        openDeepLinkSpy = nil
        openExternalURLSpy = nil
        isProcessingDeepLink = false
        processingGuardTimeout = defaultProcessingGuardTimeout
    }
}
