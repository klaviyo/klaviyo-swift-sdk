//
//  InboxStorePageTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxStorePageTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeStore() -> InboxStore {
        InboxStoreFixtures.store(appGroup: appGroup)
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

    private func ids(_ page: InboxStorePage) -> [String] {
        page.messages.map(\.id)
    }

    @Test
    func aPageIsNewestFirstBySortTime() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        await capture(store, "tm-3", secondsAfterBase: 3)
        await capture(store, "tm-2", secondsAfterBase: 2)
        let page = try await store.page(companyID: company, limit: 10, after: nil)
        #expect(ids(page) == ["tm-3", "tm-2", "tm-1"])
    }

    @Test(arguments: [0, -1])
    func aNonpositiveLimitReturnsAnEmptyPage(limit: Int) async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        let page = try await store.page(companyID: company, limit: limit, after: nil)
        #expect(page.messages.isEmpty)
        #expect(page.next == nil)
    }

    @Test
    func theCursorContinuesWhereThePreviousPageEnded() async throws {
        let store = makeStore()
        for index in 1...5 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        let first = try await store.page(companyID: company, limit: 2, after: nil)
        let second = try await store.page(companyID: company, limit: 2, after: first.next)
        let third = try await store.page(companyID: company, limit: 2, after: second.next)
        #expect(ids(first) == ["tm-5", "tm-4"])
        #expect(ids(second) == ["tm-3", "tm-2"])
        #expect(ids(third) == ["tm-1"])
        #expect(third.next == nil)
    }

    /// A row whose payload no longer decodes, such as one written before an `InboxRecord` change.
    @Test
    func aMessageThatCannotBeReadIsSkippedAndTheRestStillPage() async throws {
        let store = makeStore()
        for index in 1...5 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        try InboxStoreFixtures.execute(
            "UPDATE ZINBOXMESSAGE SET ZPAYLOAD = X'00' WHERE ZTRANSMISSIONID = 'tm-4';",
            in: appGroup
        )

        let first = try await store.page(companyID: company, limit: 2, after: nil)
        #expect(ids(first) == ["tm-5"])
        #expect(first.next != nil)
        let second = try await store.page(companyID: company, limit: 2, after: first.next)
        #expect(ids(second) == ["tm-3", "tm-2"])
        let third = try await store.page(companyID: company, limit: 2, after: second.next)
        #expect(ids(third) == ["tm-1"])
        #expect(third.next == nil)
    }

    @Test
    func aPageOfOnlyUnreadableMessagesStillHasANextCursor() async throws {
        let store = makeStore()
        for index in 1...3 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        try InboxStoreFixtures.execute("UPDATE ZINBOXMESSAGE SET ZPAYLOAD = X'00';", in: appGroup)

        let first = try await store.page(companyID: company, limit: 2, after: nil)
        #expect(first.messages.isEmpty)
        #expect(first.next != nil)
        let second = try await store.page(companyID: company, limit: 2, after: first.next)
        #expect(second.messages.isEmpty)
        #expect(second.next == nil)
    }

    @Test
    func aPageThatExactlyEndsTheInboxHasNoNextCursor() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        await capture(store, "tm-2", secondsAfterBase: 2)
        let page = try await store.page(companyID: company, limit: 2, after: nil)
        #expect(ids(page) == ["tm-2", "tm-1"])
        #expect(page.next == nil)
    }

    @Test
    func anEmptyInboxIsAnEmptyPageWithNoCursor() async throws {
        let store = makeStore()
        let page = try await store.page(companyID: company, limit: 10, after: nil)
        #expect(page.messages.isEmpty)
        #expect(page.next == nil)
    }

    @Test
    func messagesWithTheSameSortTimeAreOrderedByTransmissionIDAcrossPages() async throws {
        let store = makeStore()
        await capture(store, "tm-a", secondsAfterBase: 1)
        await capture(store, "tm-b", secondsAfterBase: 1)
        await capture(store, "tm-c", secondsAfterBase: 1)
        let first = try await store.page(companyID: company, limit: 2, after: nil)
        let second = try await store.page(companyID: company, limit: 2, after: first.next)
        #expect(ids(first) == ["tm-c", "tm-b"])
        #expect(ids(second) == ["tm-a"])
    }

    /// Page order and the cursor's `<` have to compare IDs the same way, or a message at a page boundary
    /// is skipped or repeated. Upper and lower case sort differently under binary and locale-aware
    /// comparison, so mixed case tells them apart.
    @Test
    func messagesWithTheSameSortTimePageOnceEachWhateverTheCase() async throws {
        let store = makeStore()
        let all = ["tm-B", "tm-a", "tm-Z", "tm-b", "tm-A", "tm-z", "tm-_", "tm-1"]
        for id in all {
            await capture(store, id, secondsAfterBase: 1)
        }
        var seen: [String] = []
        var cursor: InboxStoreCursor?
        repeat {
            let page = try await store.page(companyID: company, limit: 1, after: cursor)
            seen += ids(page)
            cursor = page.next
        } while cursor != nil
        #expect(seen == all.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.reversed())
    }

    @Test
    func aPageOnlyHoldsTheRequestedCompany() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        await capture(store, "other-1", secondsAfterBase: 2, company: "XyZ789")
        let page = try await store.page(companyID: company, limit: 10, after: nil)
        #expect(ids(page) == ["tm-1"])
    }

    @Test
    func aMessageCapturedBetweenPagesDoesNotShiftThePageBoundary() async throws {
        let store = makeStore()
        for index in 1...4 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        let first = try await store.page(companyID: company, limit: 2, after: nil)
        await capture(store, "tm-5", secondsAfterBase: 5)
        let second = try await store.page(companyID: company, limit: 2, after: first.next)
        #expect(ids(first) == ["tm-4", "tm-3"])
        #expect(ids(second) == ["tm-2", "tm-1"])
    }

    @Test
    func aMessageWithNoSentTimeSortsByWhenItWasReceived() async throws {
        let store = makeStore()
        await capture(store, "sent", secondsAfterBase: 10)
        let received = InboxStoreFixtures.record(
            tm: "received",
            sentAt: nil,
            receivedAt: InboxStoreFixtures.baseDate.addingTimeInterval(20)
        )
        _ = await store.capture(received, companyID: company)
        let page = try await store.page(companyID: company, limit: 1, after: nil)
        let next = try await store.page(companyID: company, limit: 1, after: page.next)
        #expect(ids(page) == ["received"])
        #expect(ids(next) == ["sent"])
    }

    // MARK: - Read and archive filters

    /// Captures one message in each combination of read and archived, newest first:
    /// `unread`, `read`, `archived-unread`, `archived-read`.
    private func captureEveryState(_ store: InboxStore) async throws {
        await capture(store, "unread", secondsAfterBase: 4)
        await capture(store, "read", secondsAfterBase: 3)
        await capture(store, "archived-unread", secondsAfterBase: 2)
        await capture(store, "archived-read", secondsAfterBase: 1)
        try await store.setRead(true, id: "read", companyID: company)
        try await store.setArchived(true, id: "archived-unread", companyID: company)
        try await store.setRead(true, id: "archived-read", companyID: company)
        try await store.setArchived(true, id: "archived-read", companyID: company)
    }

    @Test
    func aNilReadAndArchiveStateMatchesEveryMessage() async throws {
        let store = makeStore()
        try await captureEveryState(store)
        let page = try await store.page(companyID: company, limit: 10, after: nil)
        #expect(ids(page) == ["unread", "read", "archived-unread", "archived-read"])
    }

    @Test
    func aPageIsFilteredByReadState() async throws {
        let store = makeStore()
        try await captureEveryState(store)
        let unread = try await store.page(companyID: company, limit: 10, after: nil, isRead: false)
        let read = try await store.page(companyID: company, limit: 10, after: nil, isRead: true)
        #expect(ids(unread) == ["unread", "archived-unread"])
        #expect(ids(read) == ["read", "archived-read"])
    }

    @Test
    func aPageIsFilteredByArchivedState() async throws {
        let store = makeStore()
        try await captureEveryState(store)
        let active = try await store.page(companyID: company, limit: 10, after: nil, isArchived: false)
        let archived = try await store.page(companyID: company, limit: 10, after: nil, isArchived: true)
        #expect(ids(active) == ["unread", "read"])
        #expect(ids(archived) == ["archived-unread", "archived-read"])
    }

    @Test
    func aPageCombinesTheReadAndArchivedFilters() async throws {
        let store = makeStore()
        try await captureEveryState(store)
        let unreadActive = try await store.page(
            companyID: company, limit: 10, after: nil, isRead: false, isArchived: false
        )
        let readArchived = try await store.page(
            companyID: company, limit: 10, after: nil, isRead: true, isArchived: true
        )
        #expect(ids(unreadActive) == ["unread"])
        #expect(ids(readArchived) == ["archived-read"])
    }

    /// An archived unread message is still unread, so the read filter alone must return it.
    @Test
    func theReadFilterIsIndependentOfTheArchiveFilter() async throws {
        let store = makeStore()
        try await captureEveryState(store)
        let unread = try await store.page(companyID: company, limit: 10, after: nil, isRead: false)
        #expect(ids(unread) == ["unread", "archived-unread"])
    }

    @Test
    func aFilteredPageWalksOnlyMatchingMessagesAcrossPages() async throws {
        let store = makeStore()
        for index in 1...6 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        // Every even message is archived, leaving the odd ones active.
        for index in stride(from: 2, through: 6, by: 2) {
            try await store.setArchived(true, id: "tm-\(index)", companyID: company)
        }

        let first = try await store.page(companyID: company, limit: 2, after: nil, isArchived: false)
        let second = try await store.page(companyID: company, limit: 2, after: first.next, isArchived: false)
        #expect(ids(first) == ["tm-5", "tm-3"])
        #expect(first.next != nil)
        #expect(ids(second) == ["tm-1"])
        #expect(second.next == nil)
    }

    @Test
    func aFilteredPageStaysStableWhenAMessageLeavesTheFilterBetweenPages() async throws {
        let store = makeStore()
        for index in 1...4 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        let first = try await store.page(companyID: company, limit: 2, after: nil, isRead: false)
        // The message the first page ended on becomes read, so it no longer matches the filter.
        try await store.setRead(true, id: "tm-3", companyID: company)
        let second = try await store.page(companyID: company, limit: 2, after: first.next, isRead: false)
        #expect(ids(first) == ["tm-4", "tm-3"])
        #expect(ids(second) == ["tm-2", "tm-1"])
    }

    @Test
    func anUnfilteredPageReturnsArchivedMessages() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let page = try await store.page(companyID: company, limit: 10, after: nil)
        #expect(ids(page) == ["tm-1"])
    }
}

#endif
