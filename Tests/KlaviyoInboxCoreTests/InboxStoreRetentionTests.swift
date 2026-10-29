//
//  InboxStoreRetentionTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxStoreRetentionTests: XCTestCase {
    private var appGroup: InboxAppGroup!
    private let company = "AbC123"
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    private func makeStore(maxMessages: Int = 3) -> InboxStore {
        InboxStore(appGroup: appGroup, maxMessages: maxMessages)
    }

    private func capture(
        _ store: InboxStore,
        _ tm: String,
        secondsAfterBase seconds: TimeInterval,
        company: String? = nil
    ) async {
        let record = InboxStoreFixtures.record(tm: tm, sentAt: base.addingTimeInterval(seconds))
        _ = await store.capture(record, companyID: company ?? self.company)
    }

    private func present(_ store: InboxStore, _ ids: [String]) async throws -> [String] {
        var found: [String] = []
        for id in ids where try await store.message(id: id) != nil {
            found.append(id)
        }
        return found
    }

    func testTheOldestMessageBySortTimeIsEvictedOverTheLimit() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        await capture(store, "tm-2", secondsAfterBase: 2)
        await capture(store, "tm-3", secondsAfterBase: 3)
        await capture(store, "tm-4", secondsAfterBase: 4)
        let kept = try await present(store, ["tm-1", "tm-2", "tm-3", "tm-4"])
        XCTAssertEqual(kept, ["tm-2", "tm-3", "tm-4"])
    }

    func testEvictionFollowsSortTimeNotArrivalOrder() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 10)
        await capture(store, "tm-2", secondsAfterBase: 20)
        await capture(store, "tm-3", secondsAfterBase: 30)
        // Arrives last but was sent first, so it is the oldest and goes straight out.
        await capture(store, "tm-0", secondsAfterBase: 5)
        let kept = try await present(store, ["tm-0", "tm-1", "tm-2", "tm-3"])
        XCTAssertEqual(kept, ["tm-1", "tm-2", "tm-3"])
    }

    func testRetentionIsPerCompany() async throws {
        let store = makeStore()
        await capture(store, "other-1", secondsAfterBase: 1, company: "XyZ789")
        for index in 1...4 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        let kept = try await present(store, ["other-1", "tm-1", "tm-2", "tm-3", "tm-4"])
        XCTAssertEqual(kept, ["other-1", "tm-2", "tm-3", "tm-4"])
    }

    func testIdenticalSortTimesEvictTheLowestTransmissionIDFirst() async throws {
        let store = makeStore()
        await capture(store, "tm-b", secondsAfterBase: 1)
        await capture(store, "tm-a", secondsAfterBase: 1)
        await capture(store, "tm-d", secondsAfterBase: 1)
        await capture(store, "tm-c", secondsAfterBase: 1)
        let kept = try await present(store, ["tm-a", "tm-b", "tm-c", "tm-d"])
        XCTAssertEqual(kept, ["tm-b", "tm-c", "tm-d"])
    }

    func testADuplicateNeverDeletesAnything() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        await capture(store, "tm-2", secondsAfterBase: 2)
        await capture(store, "tm-3", secondsAfterBase: 3)
        // Replaying the newest at the limit must not evict the oldest.
        let replay = await store.capture(
            InboxStoreFixtures.record(tm: "tm-3", sentAt: base.addingTimeInterval(3)),
            companyID: company
        )
        XCTAssertEqual(replay, .duplicate)
        let kept = try await present(store, ["tm-1", "tm-2", "tm-3"])
        XCTAssertEqual(kept, ["tm-1", "tm-2", "tm-3"])
    }

    func testTheDefaultLimitIsOneHundred() {
        XCTAssertEqual(InboxStore.maxMessages, 100)
    }
}
