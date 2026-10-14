//
//  InboxConfigStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation
import OSLog

/// Reads and writes the Mobile Inbox configuration file in an App Group container.
///
/// The app is the only writer. Writes replace the file atomically, so a concurrent reader (the
/// Notification Service Extension) sees either the previous or the new record, never a partial
/// one. Reading never throws: a corrupt file reads as `.disabled` and an unreachable or unreadable
/// one as `.unavailable`, so capture fails closed either way.
package final class InboxConfigStore {
    package static let directoryName = "KlaviyoInbox"
    package static let fileName = "klaviyo-inbox-config.json"

    /// The extension reads this file when a push arrives, usually while the device is locked, so it
    /// must stay readable after the first unlock. Any other store in the App Group that the
    /// extension reads should use the same class.
    package static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication
    package static let writeOptions: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication
    ]

    private let group: InboxAppGroup
    private let writeLock = NSLock()

    package init(group: InboxAppGroup = .system) {
        self.group = group
    }

    package var directoryURL: URL? {
        guard let identifier = group.identifier()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxConfig.error("No \(InboxAppGroup.infoDictionaryKey, privacy: .public) entry in Info.plist; Mobile Inbox needs the App Group shared with your Notification Service Extension.")
            }
            return nil
        }
        guard let container = group.containerURL(identifier) else {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxConfig.error("App Group \(identifier, privacy: .public) is unreachable; check the App Groups capability.")
            }
            return nil
        }
        return container.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    package var fileURL: URL? {
        directoryURL?.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    package func enablement() -> InboxEnablement {
        guard let fileURL else { return .unavailable }
        switch readRecord(at: fileURL) {
        case .absent: return .neverRegistered
        case .unreadable: return .unavailable
        case .corrupt: return .disabled
        case let .record(record):
            guard record.enabled else { return .disabled }
            return .enabled(localRetentionLimit: InboxLimits.clampedRetention(record.localRetentionLimit))
        }
    }

    package func enable(localRetentionLimit: Int) throws {
        let limit = InboxLimits.clampedRetention(localRetentionLimit)
        try update { _ in InboxConfigRecord(enabled: true, localRetentionLimit: limit) }
    }

    package func disable() throws {
        try update { existing in
            InboxConfigRecord(
                enabled: false,
                localRetentionLimit: existing?.localRetentionLimit ?? InboxLimits.defaultRetention
            )
        }
    }

    private func update(_ makeRecord: (InboxConfigRecord?) -> InboxConfigRecord) throws {
        guard let directoryURL, let fileURL else {
            throw InboxConfigError.appGroupUnavailable
        }
        writeLock.lock()
        defer { writeLock.unlock() }

        let existing: InboxConfigRecord?
        if case let .record(record) = readRecord(at: fileURL) {
            existing = record
        } else {
            existing = nil
        }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: Self.fileProtection]
            )
            // `createDirectory` ignores attributes for a directory that already exists. The file carries
            // its own protection class, so a failure here is logged rather than failing the write.
            do {
                try fileManager.setAttributes(
                    [.protectionKey: Self.fileProtection],
                    ofItemAtPath: directoryURL.path
                )
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.mobileInboxConfig.warning(
                        "Unable to set protection on Mobile Inbox directory: \(error, privacy: .public)"
                    )
                }
            }
            let data = try JSONEncoder().encode(makeRecord(existing))
            try data.write(to: fileURL, options: Self.writeOptions)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxConfig.error("Unable to save Mobile Inbox settings: \(error, privacy: .public)")
            }
            throw InboxConfigError.writeFailed
        }
    }

    private enum ReadResult {
        case absent
        /// The file exists but could not be read (logged), for example while the device is locked.
        case unreadable
        /// The file was read but is not a supported record (logged).
        case corrupt
        case record(InboxConfigRecord)
    }

    private func readRecord(at fileURL: URL) -> ReadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            return .absent
        } catch {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxConfig.error("Unable to read Mobile Inbox settings: \(error, privacy: .public)")
            }
            return .unreadable
        }
        do {
            let record = try JSONDecoder().decode(InboxConfigRecord.self, from: data)
            guard (1...InboxConfigRecord.currentVersion).contains(record.version) else {
                if #available(iOS 14.0, *) {
                    Logger.mobileInboxConfig.error("Mobile Inbox settings version \(record.version) is not supported.")
                }
                return .corrupt
            }
            return .record(record)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.mobileInboxConfig.error("Unable to decode Mobile Inbox settings: \(error, privacy: .public)")
            }
            return .corrupt
        }
    }
}
