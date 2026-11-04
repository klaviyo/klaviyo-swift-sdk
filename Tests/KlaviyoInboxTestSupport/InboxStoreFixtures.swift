//
//  InboxStoreFixtures.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import SQLite3

/// Shared setup for tests that need a store: a throwaway App Group and ready-made records.
package enum InboxStoreFixtures {
    package static let groupIdentifier = "group.test"
    package static let company = "AbC123"
    /// The instant sent times are measured from, so ordering in a test reads as small offsets.
    package static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    /// An `InboxAppGroup` backed by a fresh temporary directory, so no test shares files with another.
    package static func temporaryAppGroup() -> InboxAppGroup {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("klaviyo-inbox-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return InboxAppGroup(
            identifier: { groupIdentifier },
            containerURL: { _ in directory }
        )
    }

    /// A store on `appGroup` that signals `changeSignal`, which counts posts by default, so a test never
    /// sends a real cross-process notification unless it asks to.
    package static func store(
        appGroup: InboxAppGroup,
        maxMessages: Int = InboxStore.defaultMaxMessages,
        changeSignal: InboxChangeSignaling = RecordingInboxChangeSignal()
    ) -> InboxStore {
        InboxStore(appGroup: appGroup, maxMessages: maxMessages, changeSignal: changeSignal)
    }

    package struct SQLFailure: Error {
        package let code: Int32
    }

    /// Runs SQL against the store file from a second connection, the way another process would.
    package static func execute(_ sql: String, in appGroup: InboxAppGroup) throws {
        guard let directory = appGroup.inboxDirectory() else { throw SQLFailure(code: SQLITE_CANTOPEN) }
        let path = directory.appendingPathComponent(InboxStore.storeFileName).path
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let opened = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
        guard opened == SQLITE_OK else { throw SQLFailure(code: opened) }
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw SQLFailure(code: result) }
    }

    /// A record with every optional field filled in, so round-trip tests exercise all of them.
    package static func record(
        tm: String,
        sentAt: Date? = nil,
        receivedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> InboxRecord {
        InboxRecord(
            attribution: InboxAttribution(
                transmissionID: tm,
                companyID: company,
                rawProperties: Data(#"{"tm":"\#(tm)","c":"\#(company)"}"#.utf8)
            ),
            title: "Sale",
            body: "50% off",
            defaultDestination: .deepLink(URL(string: "myapp://home")!),
            mediaURL: URL(string: "https://example.com/i.png"),
            mediaType: "png",
            customData: ["k1": "v1"],
            actions: [
                InboxAction(id: "a1", label: "Shop", destination: .deepLink(URL(string: "myapp://sale")!)),
                InboxAction(id: "a2", label: "Web", destination: .openUrl(URL(string: "https://example.com")!))
            ],
            sentAt: sentAt,
            receivedAt: receivedAt,
            badge: InboxBadge(apsBadge: 3, config: "set_count", value: 5, notificationCount: 7),
            transport: InboxTransportFlags(
                mutableContent: true,
                contentAvailable: false,
                priority: "10",
                sound: "default"
            )
        )
    }

    /// Captures a record sent `seconds` after `baseDate`, under `companyID`.
    @discardableResult
    package static func capture(
        _ store: InboxStore,
        _ tm: String,
        sentAfterBase seconds: TimeInterval,
        companyID: String = company
    ) async -> InboxCaptureResult {
        let record = record(tm: tm, sentAt: baseDate.addingTimeInterval(seconds))
        return await store.capture(record, companyID: companyID)
    }
}
