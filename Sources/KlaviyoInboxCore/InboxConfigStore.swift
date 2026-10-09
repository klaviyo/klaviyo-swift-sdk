//
//  InboxConfigStore.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import Foundation

/// Reads and writes the Mobile Inbox configuration file in an App Group container.
///
/// The app is the only writer. Writes replace the file atomically, so a concurrent reader (the
/// Notification Service Extension) sees either the previous or the new record, never a partial
/// one. Reading never throws: an unusable file reads as `.disabled`, so capture fails closed.
package final class InboxConfigStore {
    package static let directoryName = "KlaviyoInbox"
    package static let fileName = "klaviyo-inbox-config.json"

    private let group: InboxAppGroup
    private let writeLock = NSLock()

    package init(group: InboxAppGroup = .system) {
        self.group = group
    }

    package var directoryURL: URL? {
        guard let identifier = group.identifier()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else {
            InboxLog.error(
                "No \(InboxAppGroup.infoDictionaryKey) entry in Info.plist; Mobile Inbox needs the App Group " +
                    "shared with your Notification Service Extension."
            )
            return nil
        }
        guard let container = group.containerURL(identifier) else {
            InboxLog.error("App Group \(identifier) is unreachable; check the App Groups capability.")
            return nil
        }
        return container.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    package var fileURL: URL? {
        directoryURL?.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    package func enablement() -> InboxEnablement {
        guard let fileURL else { return .neverRegistered }
        guard let record = readRecord(at: fileURL) else { return .neverRegistered }
        guard record.enabled else { return .disabled }
        return .enabled(localRetentionLimit: InboxLimits.clampedRetention(record.localRetentionLimit))
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

        let existing = readRecord(at: fileURL)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(makeRecord(existing))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            InboxLog.error("Unable to save Mobile Inbox settings: \(error.localizedDescription)")
            throw InboxConfigError.writeFailed
        }
    }

    /// The persisted record, nil when the file is absent, or a disabled record when it is unusable
    /// (logged), so capture fails closed.
    private func readRecord(at fileURL: URL) -> InboxConfigRecord? {
        let unusable = InboxConfigRecord(enabled: false, localRetentionLimit: InboxLimits.defaultRetention)
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            return nil
        } catch {
            InboxLog.error("Unable to read Mobile Inbox settings: \(error.localizedDescription)")
            return unusable
        }
        do {
            let record = try JSONDecoder().decode(InboxConfigRecord.self, from: data)
            guard (1...InboxConfigRecord.currentVersion).contains(record.version) else {
                InboxLog.error("Mobile Inbox settings version \(record.version) is not supported.")
                return unusable
            }
            return record
        } catch {
            InboxLog.error("Unable to decode Mobile Inbox settings: \(error.localizedDescription)")
            return unusable
        }
    }
}
