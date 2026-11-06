//
//  InboxStoreRetentionTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import SQLite3
#if canImport(Testing)
import Testing

@Suite
struct InboxStoreRetentionTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeStore(maxMessages: Int = 3) -> InboxStore {
        InboxStore(appGroup: appGroup, maxMessages: maxMessages)
    }

    private func capture(
        _ store: InboxStore,
        _ tm: String,
        secondsAfterBase seconds: TimeInterval,
        company: String? = nil
    ) async {
        _ = await InboxStoreFixtures.capture(
            store, tm, sentAfterBase: seconds, companyID: company ?? self.company
        )
    }

    private func present(_ store: InboxStore, _ ids: [String]) async throws -> [String] {
        var found: [String] = []
        for id in ids where try await store.message(id: id) != nil {
            found.append(id)
        }
        return found
    }

    /// Runs SQL against the store file from a second connection, the way another process would.
    private func execute(_ sql: String) throws {
        let directory = try #require(appGroup.inboxDirectory())
        let path = directory.appendingPathComponent(InboxStore.storeFileName).path
        var db: OpaquePointer?
        try #require(sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test
    func aFailedTrimStillReportsTheStoredMessageAsCaptured() async throws {
        let store = InboxStore(appGroup: appGroup, maxMessages: 1)
        await capture(store, "tm-1", secondsAfterBase: 1)
        // Deleting a message now fails, so the trim after the next insert throws.
        try execute("CREATE TRIGGER failDeletes BEFORE DELETE ON ZINBOXMESSAGE BEGIN SELECT RAISE(ABORT, 'no'); END;")

        let result = await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2, companyID: company)
        #expect(result == .captured)
        let stored = try await present(store, ["tm-1", "tm-2"])
        #expect(stored == ["tm-1", "tm-2"])

        // The next capture trims everything beyond the limit, so the overshoot corrects itself.
        try execute("DROP TRIGGER failDeletes;")
        await capture(store, "tm-3", secondsAfterBase: 3)
        let kept = try await present(store, ["tm-1", "tm-2", "tm-3"])
        #expect(kept == ["tm-3"])
    }

    @Test
    func theOldestMessageBySortTimeIsEvictedOverTheLimit() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        await capture(store, "tm-2", secondsAfterBase: 2)
        await capture(store, "tm-3", secondsAfterBase: 3)
        await capture(store, "tm-4", secondsAfterBase: 4)
        let kept = try await present(store, ["tm-1", "tm-2", "tm-3", "tm-4"])
        #expect(kept == ["tm-2", "tm-3", "tm-4"])
    }

    @Test
    func evictionFollowsSortTimeNotArrivalOrder() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 10)
        await capture(store, "tm-2", secondsAfterBase: 20)
        await capture(store, "tm-3", secondsAfterBase: 30)
        // Arrives last but was sent first, so it is the oldest and goes straight out.
        await capture(store, "tm-0", secondsAfterBase: 5)
        let kept = try await present(store, ["tm-0", "tm-1", "tm-2", "tm-3"])
        #expect(kept == ["tm-1", "tm-2", "tm-3"])
    }

    @Test
    func retentionIsPerCompany() async throws {
        let store = makeStore()
        await capture(store, "other-1", secondsAfterBase: 1, company: "XyZ789")
        for index in 1...4 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        let kept = try await present(store, ["other-1", "tm-1", "tm-2", "tm-3", "tm-4"])
        #expect(kept == ["other-1", "tm-2", "tm-3", "tm-4"])
    }

    @Test
    func identicalSortTimesEvictTheLowestTransmissionIDFirst() async throws {
        let store = makeStore()
        await capture(store, "tm-b", secondsAfterBase: 1)
        await capture(store, "tm-a", secondsAfterBase: 1)
        await capture(store, "tm-d", secondsAfterBase: 1)
        await capture(store, "tm-c", secondsAfterBase: 1)
        let kept = try await present(store, ["tm-a", "tm-b", "tm-c", "tm-d"])
        #expect(kept == ["tm-b", "tm-c", "tm-d"])
    }

    @Test
    func aDuplicateNeverDeletesAnything() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        await capture(store, "tm-2", secondsAfterBase: 2)
        await capture(store, "tm-3", secondsAfterBase: 3)
        // Replaying the newest at the limit must not evict the oldest.
        let replay = await store.capture(
            InboxStoreFixtures.record(tm: "tm-3", sentAt: InboxStoreFixtures.baseDate.addingTimeInterval(3)),
            companyID: company
        )
        #expect(replay == .duplicate)
        let kept = try await present(store, ["tm-1", "tm-2", "tm-3"])
        #expect(kept == ["tm-1", "tm-2", "tm-3"])
    }

    @Test
    func theDefaultLimitIsOneHundred() {
        #expect(InboxStore.defaultMaxMessages == 100)
    }
}

#endif
