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
/// one. Reading never throws: anything unusable reads as `.neverRegistered`, so capture fails closed.
package final class InboxConfigStore {
    package static let directoryName = "KlaviyoInbox"
    package static let fileName = "klaviyo-inbox-config.json"

    private enum ReadResult {
        case absent
        case record(InboxConfigRecord)
        case unusable
    }

    private let appGroupIdentifier: String
    private let group: InboxAppGroup
    private let writeLock = NSLock()

    package init(appGroupIdentifier: String, group: InboxAppGroup = .system) {
        self.appGroupIdentifier = appGroupIdentifier
        self.group = group
    }

    package var directoryURL: URL? {
        guard !appGroupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return group.containerURL(appGroupIdentifier)?
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    package var fileURL: URL? {
        directoryURL?.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    package func enablement() -> InboxEnablement {
        guard let fileURL else {
            InboxLog.error("App Group \(appGroupIdentifier) is unavailable; Mobile Inbox is off.")
            return .neverRegistered
        }
        switch readRecord(at: fileURL) {
        case .absent, .unusable:
            return .neverRegistered
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
            InboxLog.error("App Group \(appGroupIdentifier) is unavailable; cannot save Inbox settings.")
            throw InboxConfigError.groupUnavailable
        }
        writeLock.lock()
        defer { writeLock.unlock() }

        var existing: InboxConfigRecord?
        if case let .record(record) = readRecord(at: fileURL) {
            existing = record
        }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(makeRecord(existing))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            InboxLog.error("Unable to save Mobile Inbox settings: \(error.localizedDescription)")
            throw InboxConfigError.writeFailed
        }
    }

    private func readRecord(at fileURL: URL) -> ReadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            return .absent
        } catch {
            InboxLog.error("Unable to read Mobile Inbox settings: \(error.localizedDescription)")
            return .unusable
        }
        do {
            let record = try JSONDecoder().decode(InboxConfigRecord.self, from: data)
            guard record.version <= InboxConfigRecord.currentVersion else {
                InboxLog.error("Mobile Inbox settings version \(record.version) is newer than supported.")
                return .unusable
            }
            return .record(record)
        } catch {
            InboxLog.error("Unable to decode Mobile Inbox settings: \(error.localizedDescription)")
            return .unusable
        }
    }
}
