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
    /// The one clearer the observer and ``settle()`` share, so a reset is applied once between them.
    static let shared = ResetClearer(
        pendingMarker: ProfileResetSignal.pendingMarker,
        acknowledge: ProfileResetSignal.acknowledge,
        clearAll: { try await InboxStore.shared.clearAll() }
    )

    /// Starts the observer once per process. Safe to call from any thread and as often as needed.
    static func startIfNeeded() {
        _ = started
    }

    // A `static let` initializer runs once, even under concurrent first access.
    private static let started: Bool = {
        let resets = ProfileResetSignal.resets()
        Task.detached(priority: .utility) {
            await run(resets: resets, clearer: shared)
        }
        return true
    }()

    /// Makes a pending reset take effect before the caller reads or changes the inbox, so a read does not see
    /// the previous profile's messages. The reset is applied here, on the caller's own task, instead of
    /// waiting for the observer's, and a clear the observer already started is awaited, not repeated.
    ///
    /// This covers every reset published before the call reaches its last check. A reset published after
    /// that overlaps the access that follows, and the observer clears it moments later.
    ///
    /// - Throws: When the clear fails. The read must not go ahead then, because it could return the
    ///   previous profile's messages.
    static func settle() async throws {
        try await shared.clearPending()
    }

    /// Clears for the reset that is pending now, then for every one after it, one at a time, until `resets`
    /// ends. `resets` must already be subscribed, so a reset between subscribing and reading the marker
    /// is not missed.
    static func run(resets: AsyncStream<Void>, clearer: ResetClearer) async {
        func clearIfPending() async {
            do {
                try await clearer.clearPending()
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

/// Applies the pending reset: clears the inbox, then removes the marker once the clear has succeeded.
///
/// Callers share one clear per marker. A caller that finds its marker already being cleared awaits that
/// clear and gets its result, and one that arrives after it finished finds no pending marker and does
/// nothing. Clearing deletes every row, so a second delete for the same reset could remove a message the
/// Notification Service Extension captured for the new profile after the first delete finished.
final class ResetClearer: @unchecked Sendable {
    private let pendingMarker: @Sendable () -> UUID?
    private let acknowledge: @Sendable (UUID) -> Void
    private let clearAll: @Sendable () async throws -> Void
    /// Guards `inFlight`.
    private let lock = NSLock()
    private var inFlight: (marker: UUID, task: Task<Void, Error>)?

    init(
        pendingMarker: @escaping @Sendable () -> UUID?,
        acknowledge: @escaping @Sendable (UUID) -> Void,
        clearAll: @escaping @Sendable () async throws -> Void
    ) {
        self.pendingMarker = pendingMarker
        self.acknowledge = acknowledge
        self.clearAll = clearAll
    }

    /// Clears the inbox while a reset is pending. Returns normally when nothing is pending or every clear
    /// worked, and throws when a clear failed, leaving that marker for a retry.
    ///
    /// It reads the marker again after each clear, because a newer reset can arrive while a clear runs.
    /// It stops if the same marker is still there after its clear, so a marker that cannot be removed
    /// does not cause repeated clears within one call.
    func clearPending() async throws {
        var lastCleared: UUID?
        while let marker = pendingMarker(), marker != lastCleared {
            try await clear(marker)
            lastCleared = marker
        }
    }

    private func clear(_ marker: UUID) async throws {
        let task: Task<Void, Error>? = lock.withLock {
            if let inFlight, inFlight.marker == marker { return inFlight.task }
            // The clear this caller read the marker for may have finished since: it acknowledges before it
            // leaves `inFlight`, so a missing entry with the marker gone means there is nothing left to do.
            guard pendingMarker() == marker else { return nil }
            let task = Task { [self] in
                defer { finish(marker) }
                try await clearAll()
                acknowledge(marker)
            }
            inFlight = (marker, task)
            return task
        }
        try await task?.value
    }

    private func finish(_ marker: UUID) {
        lock.withLock {
            if inFlight?.marker == marker { inFlight = nil }
        }
    }
}
