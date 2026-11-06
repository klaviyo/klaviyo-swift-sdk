//
//  InboxStoreOpener.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import CoreData
import Foundation
import SQLite3

/// Opens the Inbox's persistent store so that a bad file can never block capture. A store that is
/// corrupt, or written by a different model version, is deleted and rebuilt, and the messages in it are
/// lost. Any other failure leaves the files alone and fails the open, so the next capture tries again:
/// losing one capture is better than deleting messages that may be fine.
///
/// There is no migration: the model has one version. The first schema change has to add one here.
struct InboxStoreOpener {
    let diagnostics: (InboxStoreEvent) -> Void

    /// The store file and the files SQLite keeps beside it in WAL mode.
    private static let sidecarSuffixes = ["", "-wal", "-shm"]
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private static let lockFileName = "klaviyo-inbox.lock"
    /// Up to about 0.4 s waiting for another process to finish opening, well under the 1 s capture timeout.
    private static let lockAttempts = 40
    private static let lockRetryDelay: TimeInterval = 0.01
    /// Up to about 0.12 s retrying a transient SQLite failure, such as another process still creating the file.
    private static let transientAttempts = 5
    private static let transientRetryDelay: TimeInterval = 0.03

    /// Serializes opening across processes with a non-blocking `flock`, so the wait is bounded and a stuck
    /// holder cannot block the store. Without it, the app and the extension creating the store at the same
    /// moment make Core Data fail one of them with a plain Cocoa write error ("File unexpectedly appeared
    /// during sanity check") that carries no SQLite code, and a healthy store gets rebuilt.
    /// `NSFileCoordinator` also passes the tests, but it waits as long as the holder does, with no timeout.
    /// Best effort: if the lock cannot be taken in time, opening proceeds without it, but a store that
    /// needs a rebuild is then left alone, because deleting files another process may have open can corrupt
    /// them. The C calls are `Darwin.`-qualified only because a bare `open` resolves to this method.
    func open(_ coordinator: NSPersistentStoreCoordinator, at url: URL) throws {
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
        try openLocked(coordinator, at: url, holdsLock: locked)
    }

    private func openLocked(_ coordinator: NSPersistentStoreCoordinator, at url: URL, holdsLock: Bool) throws {
        let started = ProcessInfo.processInfo.systemUptime
        protectDirectory(of: url)
        do {
            try openRetryingTransientFailures(coordinator, at: url)
        } catch {
            guard InboxStoreError.indicatesCorruption(error) else {
                throw InboxStoreError.underlying(error)
            }
            guard holdsLock else {
                diagnostics(.degraded(reason: "store needs a rebuild but the open lock is not held"))
                throw InboxStoreError.underlying(error)
            }
            rebuild(url, after: error)
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

    /// Deletes the store and its sidecar files so a fresh one can be created in their place. The diagnostic
    /// carries the error's domain and code only, with no message content.
    private func rebuild(_ url: URL, after error: Error) {
        for suffix in Self.sidecarSuffixes {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        let nsError = error as NSError
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
            .map { " / \($0.domain) \($0.code)" } ?? ""
        diagnostics(.recovered(reason: "store failed to open (\(nsError.domain) \(nsError.code)\(underlying))"))
    }
}

extension InboxStoreError {
    /// Failures that say nothing about the file's content: another process holds a lock or is still
    /// creating the file, the disk is full, or memory ran out. The open is retried briefly.
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

    /// The only failures that justify deleting the store: the file is corrupt or not a database, or it was
    /// written by a model this build cannot open. Everything else, including errors that carry no SQLite
    /// code, leaves the store alone and fails the open.
    package static func indicatesCorruption(_ error: Error) -> Bool {
        if let sqlite = sqliteError(in: error) {
            return corruptionPrimaryCodes.contains(sqlite.code & primaryCodeMask)
        }
        if case let .underlying(inner)? = error as? InboxStoreError { return indicatesCorruption(inner) }
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain && incompatibleModelCodes.contains(cocoa.code)
    }

    /// SQLite primary result codes: CORRUPT, NOTADB.
    private static let corruptionPrimaryCodes: Set<Int> = [Int(SQLITE_CORRUPT), Int(SQLITE_NOTADB)]
    /// `NSPersistentStoreIncompatibleVersionHashError` and `NSMigrationMissingSourceModelError`.
    private static let incompatibleModelCodes: Set<Int> = [134_100, 134_130]

    /// The SQLite error behind `error`, looking through `InboxStoreError.underlying` and one level of
    /// Cocoa wrapping. Core Data reports the code either as an underlying error or, for a file that is not
    /// a database, as a number under the `NSSQLiteErrorDomain` key of `userInfo`.
    private static func sqliteError(in error: Error) -> NSError? {
        if case let .underlying(inner)? = error as? InboxStoreError { return sqliteError(in: inner) }
        let nsError = error as NSError
        if nsError.domain == NSSQLiteErrorDomain { return nsError }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSSQLiteErrorDomain {
            return underlying
        }
        if let code = (nsError.userInfo[NSSQLiteErrorDomain] as? NSNumber)?.intValue {
            return NSError(domain: NSSQLiteErrorDomain, code: code)
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
