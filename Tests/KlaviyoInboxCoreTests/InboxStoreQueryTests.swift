//
//  InboxStoreQueryTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxStoreQueryTests: XCTestCase {
    private var appGroup: InboxAppGroup!
    private let company = InboxStoreFixtures.company

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    private func makeStore(maxMessages: Int = InboxStore.maxMessages) -> InboxStore {
        InboxStore(appGroup: appGroup, maxMessages: maxMessages)
    }

    @discardableResult
    private func capture(
        _ store: InboxStore,
        _ tm: String,
        at seconds: TimeInterval,
        company: String? = nil
    ) async -> InboxCaptureResult {
        await InboxStoreFixtures.capture(
            store, tm, sentAfterBase: seconds, companyID: company ?? self.company
        )
    }

    private func query(
        isRead: Bool? = nil,
        isArchived: Bool? = nil,
        limit: Int = 50,
        cursor: InboxStoreCursor? = nil
    ) -> InboxStoreQuery {
        InboxStoreQuery(
            companyID: company,
            isRead: isRead,
            isArchived: isArchived,
            limit: limit,
            cursor: cursor
        )
    }

    private func ids(_ page: InboxStorePage) -> [String] {
        page.messages.map(\.id)
    }

    // MARK: - Paging

    func testNewestComesFirst() async throws {
        let store = makeStore()
        await capture(store, "tm-1", at: 1)
        await capture(store, "tm-3", at: 3)
        await capture(store, "tm-2", at: 2)
        let page = try await store.fetch(query())
        XCTAssertEqual(ids(page), ["tm-3", "tm-2", "tm-1"])
        XCTAssertNil(page.nextCursor)
    }

    func testIdenticalSortTimesOrderByTransmissionIDDescending() async throws {
        let store = makeStore()
        await capture(store, "tm-a", at: 1)
        await capture(store, "tm-c", at: 1)
        await capture(store, "tm-b", at: 1)
        let page = try await store.fetch(query())
        XCTAssertEqual(ids(page), ["tm-c", "tm-b", "tm-a"])
    }

    func testACursorContinuesWithoutRepeatingAnything() async throws {
        let store = makeStore()
        for index in 1...5 { await capture(store, "tm-\(index)", at: TimeInterval(index)) }
        let first = try await store.fetch(query(limit: 2))
        XCTAssertEqual(ids(first), ["tm-5", "tm-4"])
        let second = try await store.fetch(query(limit: 2, cursor: first.nextCursor))
        XCTAssertEqual(ids(second), ["tm-3", "tm-2"])
        let third = try await store.fetch(query(limit: 2, cursor: second.nextCursor))
        XCTAssertEqual(ids(third), ["tm-1"])
        XCTAssertNil(third.nextCursor)
    }

    func testACursorStaysStableWhenNewerMessagesArriveBetweenPages() async throws {
        let store = makeStore()
        for index in 1...4 { await capture(store, "tm-\(index)", at: TimeInterval(index)) }
        let first = try await store.fetch(query(limit: 2))
        await capture(store, "tm-9", at: 9)
        let second = try await store.fetch(query(limit: 2, cursor: first.nextCursor))
        XCTAssertEqual(ids(first), ["tm-4", "tm-3"])
        XCTAssertEqual(ids(second), ["tm-2", "tm-1"])
    }

    func testAnotherCompanysMessagesAreNeverReturned() async throws {
        let store = makeStore()
        await capture(store, "tm-1", at: 1)
        await capture(store, "other-1", at: 2, company: "XyZ789")
        let page = try await store.fetch(query())
        XCTAssertEqual(ids(page), ["tm-1"])
    }

    // MARK: - Filters and state

    func testReadAndArchivedFilters() async throws {
        let store = makeStore()
        for index in 1...4 { await capture(store, "tm-\(index)", at: TimeInterval(index)) }
        try await store.setState(.read, ids: ["tm-1", "tm-2"])
        try await store.setState(.archive, ids: ["tm-2", "tm-3"])
        let unread = try await store.fetch(query(isRead: false))
        let read = try await store.fetch(query(isRead: true))
        let archived = try await store.fetch(query(isArchived: true))
        let live = try await store.fetch(query(isArchived: false))
        XCTAssertEqual(ids(unread), ["tm-4", "tm-3"])
        XCTAssertEqual(ids(read), ["tm-2", "tm-1"])
        XCTAssertEqual(ids(archived), ["tm-3", "tm-2"])
        XCTAssertEqual(ids(live), ["tm-4", "tm-1"])
    }

    func testEachStateChangeTakesEffect() async throws {
        let store = makeStore()
        await capture(store, "tm-1", at: 1)
        try await store.setState(.read, ids: ["tm-1"])
        var stored = try await store.message(id: "tm-1")
        XCTAssertEqual(stored?.isRead, true)
        try await store.setState(.unread, ids: ["tm-1"])
        stored = try await store.message(id: "tm-1")
        XCTAssertEqual(stored?.isRead, false)
        try await store.setState(.archive, ids: ["tm-1"])
        stored = try await store.message(id: "tm-1")
        XCTAssertEqual(stored?.isArchived, true)
        try await store.setState(.unarchive, ids: ["tm-1"])
        stored = try await store.message(id: "tm-1")
        XCTAssertEqual(stored?.isArchived, false)
    }

    func testRepeatingAStateIsANoOpAndUnknownIDsAreIgnored() async throws {
        let store = makeStore()
        await capture(store, "tm-1", at: 1)
        try await store.setState(.read, ids: ["tm-1", "missing"])
        try await store.setState(.read, ids: ["tm-1"])
        let stored = try await store.message(id: "tm-1")
        XCTAssertEqual(stored?.isRead, true)
        XCTAssertEqual(stored?.isArchived, false)
    }

    func testAReplayDoesNotResetReadOrArchivedState() async throws {
        let store = makeStore()
        await capture(store, "tm-1", at: 1)
        try await store.setState(.read, ids: ["tm-1"])
        try await store.setState(.archive, ids: ["tm-1"])
        let replay = await capture(store, "tm-1", at: 1)
        XCTAssertEqual(replay, .duplicate)
        let stored = try await store.message(id: "tm-1")
        XCTAssertEqual(stored?.isRead, true)
        XCTAssertEqual(stored?.isArchived, true)
    }

    func testAReplayFromAnotherStoreDoesNotResetState() async throws {
        let first = makeStore()
        await capture(first, "tm-1", at: 1)
        try await first.setState(.read, ids: ["tm-1"])
        let second = makeStore()
        let replay = await capture(second, "tm-1", at: 1)
        XCTAssertEqual(replay, .duplicate)
        let stored = try await second.message(id: "tm-1")
        XCTAssertEqual(stored?.isRead, true)
    }

    func testArchivedMessagesStillCountTowardRetention() async throws {
        let store = makeStore(maxMessages: 2)
        await capture(store, "tm-1", at: 1)
        try await store.setState(.archive, ids: ["tm-1"])
        await capture(store, "tm-2", at: 2)
        await capture(store, "tm-3", at: 3)
        let oldest = try await store.message(id: "tm-1")
        XCTAssertNil(oldest)
        let page = try await store.fetch(query())
        XCTAssertEqual(ids(page), ["tm-3", "tm-2"])
    }

    // MARK: - Clear

    func testClearRemovesOnlyThatCompany() async throws {
        let store = makeStore()
        await capture(store, "tm-1", at: 1)
        await capture(store, "other-1", at: 2, company: "XyZ789")
        try await store.clear(companyID: company)
        let remaining = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        XCTAssertNil(remaining)
        XCTAssertNotNil(other)
    }

    func testClearAllRemovesEverythingAndAMessageCanBeCapturedAgain() async throws {
        let store = makeStore()
        await capture(store, "tm-1", at: 1)
        await capture(store, "other-1", at: 2, company: "XyZ789")
        try await store.clearAll()
        let first = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        XCTAssertNil(first)
        XCTAssertNil(other)
        let again = await capture(store, "tm-1", at: 1)
        XCTAssertEqual(again, .captured)
    }
}
