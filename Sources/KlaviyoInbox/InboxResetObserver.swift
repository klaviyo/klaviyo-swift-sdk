//
//  InboxResetObserver.swift
//  klaviyo-swift-sdk
//

import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import OSLog

/// Clears the inbox when the app resets the profile, so one profile's messages are never shown to the
/// next. `KlaviyoSwift` cannot import this module, so it reports a reset through Core's
/// ``ProfileResetSignal``, and this observer acts on it.
///
/// It starts the first time the app reads ``KlaviyoSDKModule/mobileInbox``. A reset from before that is
/// found in the signal's persisted marker, in this launch or an earlier one, and the marker is removed only
/// once the clear has succeeded, so a failed clear is tried again on the next reset or launch.
///
/// - Note: A reset that happens before the app first reads `mobileInbox` is applied at that read. Any
///   message the Notification Service Extension captured for the new profile in between is cleared too.
enum InboxResetObserver {
    /// Starts the observer once per process. Safe to call from any thread and as often as needed.
    static func startIfNeeded() {
        _ = started
    }

    // A `static let` initializer runs once, even under concurrent first access.
    private static let started: Bool = {
        let resets = ProfileResetSignal.resets()
        Task.detached(priority: .utility) {
            await run(
                resets: resets,
                pendingMarker: ProfileResetSignal.pendingMarker,
                acknowledge: ProfileResetSignal.acknowledge,
                clearAll: { try await InboxStore.shared.clearAll() }
            )
        }
        return true
    }()

    /// Clears the inbox if a reset is pending, and removes the marker once the clear has succeeded. Returns
    /// normally when nothing was pending or the clear worked, and throws when the clear failed, leaving the
    /// marker for a retry.
    ///
    /// The observer's loop and ``settle()`` can both call this at once. That is harmless: `clearAll` is
    /// idempotent, and acknowledging removes a marker only if it is still the one that was read.
    static func clearPendingReset(
        pendingMarker: @Sendable () -> UUID?,
        acknowledge: @Sendable (UUID) -> Void,
        clearAll: @Sendable () async throws -> Void
    ) async throws {
        guard let marker = pendingMarker() else { return }
        try await clearAll()
        acknowledge(marker)
    }

    /// Makes a pending reset take effect before the caller reads or changes the inbox, so a read never sees
    /// the previous profile's messages. The reset is applied here, on the caller's own task, instead of
    /// waiting for the observer's.
    ///
    /// - Throws: When the clear fails. The read must not go ahead then, because it could return the
    ///   previous profile's messages.
    static func settle() async throws {
        try await clearPendingReset(
            pendingMarker: ProfileResetSignal.pendingMarker,
            acknowledge: ProfileResetSignal.acknowledge,
            clearAll: { try await InboxStore.shared.clearAll() }
        )
    }

    /// Clears for the reset that is pending now, then for every one after it, one at a time, until `resets`
    /// ends. `resets` must already be subscribed, so a reset between subscribing and reading the marker
    /// is not missed.
    static func run(
        resets: AsyncStream<Void>,
        pendingMarker: @Sendable () -> UUID?,
        acknowledge: @Sendable (UUID) -> Void,
        clearAll: @Sendable () async throws -> Void
    ) async {
        func clearIfPending() async {
            do {
                try await clearPendingReset(pendingMarker: pendingMarker, acknowledge: acknowledge, clearAll: clearAll)
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.mobileInbox.error("Could not clear the inbox on profile reset. It will be tried again.")
                }
            }
        }

        await clearIfPending()
        for await _ in resets {
            await clearIfPending()
        }
    }
}
