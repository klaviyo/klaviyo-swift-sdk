//
//  InboxStoreOpener.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData
import Foundation
import SQLite3

/// Opens the Inbox's persistent store so that a bad file can never block capture. A store that cannot
/// be opened, whether corrupt, unreadable, or written by a different model version, is deleted and
/// rebuilt, and the messages in it are lost.
///
/// There is no migration: the model has one version. The first schema change has to add one here.
struct InboxStoreOpener {
    let diagnostics: (InboxStoreEvent) -> Void

    /// The store file and the files SQLite keeps beside it in WAL mode.
    private static let sidecarSuffixes = ["", "-wal", "-shm"]
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    /// Opening retries briefly on a transient failure, because the app and the extension can both create
    /// the store on their first capture at the same moment, and one then sees the other's half-built file.
    private static let lockFileName = "klaviyo-inbox.lock"
    /// Up to about 0.4 s waiting for another process to finish opening, well under the 1 s capture timeout.
    private static let lockAttempts = 40
    private static let lockRetryDelay: TimeInterval = 0.01
    private static let transientAttempts = 5
    private static let transientRetryDelay: TimeInterval = 0.03

    /// Serializes opening across processes. Without it, the app and the extension creating the store at the
    /// same moment make Core Data fail one of them with a plain Cocoa write error ("File unexpectedly
    /// appeared during sanity check") that carries no SQLite code, and a healthy store gets rebuilt.
    /// Best effort: if the lock cannot be taken in time, opening proceeds without it.
    ///
    /// - Parameter rebuildTransientFailures: Set once this store has already failed to open. A failure
    ///   that looked transient the first time is then treated as the file's problem, so a store that keeps
    ///   returning a disk I/O error is rebuilt instead of failing every capture for the life of the install.
    func open(
        _ coordinator: NSPersistentStoreCoordinator,
        at url: URL,
        rebuildTransientFailures: Bool = false
    ) throws {
        let lockPath = url.deletingLastPathComponent().appendingPathComponent(Self.lockFileName).path
        let descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o600)
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }
        var attempts = 0
        var locked = descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0
        while descriptor >= 0, !locked, attempts < Self.lockAttempts {
            attempts += 1
            Thread.sleep(forTimeInterval: Self.lockRetryDelay)
            locked = flock(descriptor, LOCK_EX | LOCK_NB) == 0
        }
        defer { if locked { flock(descriptor, LOCK_UN) } }
        try openLocked(coordinator, at: url, rebuildTransientFailures: rebuildTransientFailures)
    }

    private func openLocked(
        _ coordinator: NSPersistentStoreCoordinator,
        at url: URL,
        rebuildTransientFailures: Bool
    ) throws {
        let started = ProcessInfo.processInfo.systemUptime
        protectDirectory(of: url)
        do {
            try openRetryingTransientFailures(coordinator, at: url)
        } catch {
            if InboxStoreError.isTransient(error), !rebuildTransientFailures {
                throw InboxStoreError.underlying(error)
            }
            rebuild(url, reason: Self.reason(for: error))
            do {
                try addStore(to: coordinator, at: url)
            } catch {
                diagnostics(.degraded(reason: "store could not be rebuilt"))
                throw InboxStoreError.underlying(error)
            }
        }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        diagnostics(.opened(milliseconds: milliseconds))
    }

    /// What went wrong, as the error's domain and code only: enough to diagnose, with no message content.
    private static func reason(for error: Error) -> String {
        let nsError = error as NSError
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { " / \($0.domain) \($0.code)" } ?? ""
        return "store failed to open (\(nsError.domain) \(nsError.code)\(underlying))"
    }

    // MARK: - Opening

    private func openRetryingTransientFailures(_ coordinator: NSPersistentStoreCoordinator, at url: URL) throws {
        var attempt = 1
        while true {
            do {
                try addStore(to: coordinator, at: url)
                return
            } catch {
                guard InboxStoreError.isTransient(error), attempt < Self.transientAttempts else { throw error }
                attempt += 1
                diagnostics(.lockContention(retries: attempt - 1))
                Thread.sleep(forTimeInterval: Self.transientRetryDelay)
            }
        }
    }

    private func addStore(to coordinator: NSPersistentStoreCoordinator, at url: URL) throws {
        let options: [AnyHashable: Any] = [
            // The extension must be able to write while the device is locked.
            NSPersistentStoreFileProtectionKey: Self.protection,
            NSSQLitePragmasOption: [
                "journal_mode": "WAL",
                "busy_timeout": String(InboxStore.busyTimeoutMilliseconds),
                // Freed pages are zeroed, so a clear actually removes message text from disk.
                "secure_delete": "ON"
            ]
        ]
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: url,
            options: options
        )
    }

    /// Directory protection is inherited by files SQLite creates later (`-wal`, `-shm`), which the
    /// store's own option does not reach. Best effort: platforms that do not support it ignore it.
    private func protectDirectory(of url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: Self.protection],
            ofItemAtPath: url.deletingLastPathComponent().path
        )
    }

    // MARK: - Rebuild

    /// Deletes the store and its sidecar files so a fresh one can be created in their place.
    private func rebuild(_ url: URL, reason: String) {
        removeStoreFiles(at: url)
        diagnostics(.recovered(reason: reason))
    }

    private func removeStoreFiles(at url: URL) {
        for suffix in Self.sidecarSuffixes {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

extension InboxStoreError {
    /// Failures that say nothing about the file's content: another process holds a lock or is still
    /// creating the file, the disk is full, or memory ran out. The store is left alone, never
    /// rebuilt, and the open is retried or the next capture tries again.
    ///
    /// SQLite reports extended codes (for example 6922, a disk I/O error from a file that moved under an
    /// open connection), so only the low byte, the primary code, is compared.
    package static func isTransient(_ error: Error) -> Bool {
        guard let sqlite = sqliteError(in: error) else { return false }
        return transientPrimaryCodes.contains(sqlite.code & primaryCodeMask)
    }

    /// SQLite primary result codes: BUSY, LOCKED, NOMEM, IOERR, FULL.
    private static let transientPrimaryCodes: Set<Int> = [
        Int(SQLITE_BUSY), Int(SQLITE_LOCKED), Int(SQLITE_NOMEM), Int(SQLITE_IOERR), Int(SQLITE_FULL)
    ]
    private static let primaryCodeMask = 0xFF

    /// The SQLite error behind `error`, looking through `InboxStoreError.underlying` and one level of
    /// Cocoa wrapping.
    private static func sqliteError(in error: Error) -> NSError? {
        if case let .underlying(inner)? = error as? InboxStoreError { return sqliteError(in: inner) }
        let nsError = error as NSError
        if nsError.domain == NSSQLiteErrorDomain { return nsError }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSSQLiteErrorDomain {
            return underlying
        }
        return nil
    }

    /// Reported for a store that could not be reached at all, where there is no error code to give.
    package static let unavailableCode = -1

    /// A stable number for a diagnostic: the SQLite code when there is one, else the error's own code.
    /// Carries no message text.
    package static func diagnosticCode(for error: Error) -> Int {
        if case .unavailable? = error as? InboxStoreError { return unavailableCode }
        if let sqlite = sqliteError(in: error) { return sqlite.code }
        if case let .underlying(inner)? = error as? InboxStoreError { return (inner as NSError).code }
        return (error as NSError).code
    }
}
