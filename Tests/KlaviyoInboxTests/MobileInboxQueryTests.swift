//
//  MobileInboxQueryTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/16/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

/// The public query's filters and the store count behind ``MobileInbox/fetchUnreadCount()``, read
/// through the inbox the way a host uses them.
@Suite
struct MobileInboxQueryTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeInbox(company: String?) -> (inbox: MobileInbox, store: InboxStore) {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        return (MobileInbox(store: store, companyID: { company }), store)
    }

    private func capture(_ store: InboxStore, _ id: String, secondsAfterBase seconds: TimeInterval) async {
        await InboxStoreFixtures.capture(store, id, sentAfterBase: seconds)
    }

    // MARK: - Filters

    @Test
    func theDefaultPageLeavesOutArchivedMessages() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, "active", secondsAfterBase: 2)
        await capture(store, "archived", secondsAfterBase: 1)
        try await inbox.setMessageState(.archived, for: "archived")
        let page = try await inbox.fetchPage()
        #expect(page.messages.map(\.id) == ["active"])
    }

    @Test
    func aPageCanAskForArchivedMessages() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, "active", secondsAfterBase: 2)
        await capture(store, "archived", secondsAfterBase: 1)
        try await inbox.setMessageState(.archived, for: "archived")
        let archived = try await inbox.fetchPage(InboxQuery(archiveFilter: .archived))
        let all = try await inbox.fetchPage(InboxQuery(archiveFilter: .all))
        #expect(archived.messages.map(\.id) == ["archived"])
        #expect(all.messages.map(\.id) == ["active", "archived"])
    }

    @Test
    func aPageIsFilteredByReadState() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, "unread", secondsAfterBase: 2)
        await capture(store, "read", secondsAfterBase: 1)
        try await inbox.setMessageState(.read, for: "read")
        let unread = try await inbox.fetchPage(InboxQuery(readFilter: .unread))
        let read = try await inbox.fetchPage(InboxQuery(readFilter: .read))
        #expect(unread.messages.map(\.id) == ["unread"])
        #expect(read.messages.map(\.id) == ["read"])
    }

    /// An archived unread message is still unread: the filters are independent.
    @Test
    func anArchivedUnreadMessageIsReturnedByTheUnreadFilterWithEveryArchiveState() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, "tm-1", secondsAfterBase: 1)
        try await inbox.setMessageState(.archived, for: "tm-1")
        let page = try await inbox.fetchPage(InboxQuery(readFilter: .unread, archiveFilter: .all))
        #expect(page.messages.map(\.id) == ["tm-1"])
    }

    @Test
    func aFilteredCursorWalksOnlyMatchingMessages() async throws {
        let (inbox, store) = makeInbox(company: company)
        for index in 1...5 {
            await capture(store, "tm-\(index)", secondsAfterBase: TimeInterval(index))
        }
        try await inbox.setMessageState(.read, for: "tm-4")
        try await inbox.setMessageState(.read, for: "tm-2")
        let first = try await inbox.fetchPage(InboxQuery(pageSize: 2, readFilter: .unread))
        let second = try await inbox.fetchPage(
            InboxQuery(pageSize: 2, cursor: first.nextCursor, readFilter: .unread)
        )
        #expect(first.messages.map(\.id) == ["tm-5", "tm-3"])
        #expect(second.messages.map(\.id) == ["tm-1"])
        #expect(second.nextCursor == nil)
    }

    // MARK: - Unread count

    @Test
    func theUnreadCountBeforeTheSDKIsInitializedIsZero() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await capture(store, "tm-1", secondsAfterBase: 1)
        let unreadCount = try await inbox.fetchUnreadCount()
        #expect(unreadCount == 0)
    }

    @Test
    func theUnreadCountExcludesReadAndArchivedMessages() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, "unread", secondsAfterBase: 4)
        await capture(store, "read", secondsAfterBase: 3)
        await capture(store, "archived", secondsAfterBase: 2)
        try await inbox.setMessageState(.read, for: "read")
        try await inbox.setMessageState(.archived, for: "archived")
        let unreadCount = try await inbox.fetchUnreadCount()
        #expect(unreadCount == 1)
    }

    @Test
    func theUnreadCountIsForTheInitializedCompanyOnly() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, "mine", secondsAfterBase: 1)
        await InboxStoreFixtures.capture(store, "theirs", sentAfterBase: 2, companyID: "XyZ789")
        let unreadCount = try await inbox.fetchUnreadCount()
        #expect(unreadCount == 1)
    }

    @Test
    func theUnreadCountFollowsAStateChange() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, "tm-1", secondsAfterBase: 1)
        let unread = try await inbox.fetchUnreadCount()
        #expect(unread == 1)
        try await inbox.setMessageState(.read, for: "tm-1")
        let read = try await inbox.fetchUnreadCount()
        #expect(read == 0)
        try await inbox.setMessageState(.unread, for: "tm-1")
        let unreadAgain = try await inbox.fetchUnreadCount()
        #expect(unreadAgain == 1)
    }

    @Test
    func theUnreadCountIsZeroForAnEmptyInbox() async throws {
        let (inbox, _) = makeInbox(company: company)
        let unreadCount = try await inbox.fetchUnreadCount()
        #expect(unreadCount == 0)
    }

    @Test
    func aStoreThatCannotBeReachedFailsTheUnreadCountWithStorageFailure() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let inbox = MobileInbox(store: InboxStoreFixtures.store(appGroup: unreachable), companyID: { "AbC123" })
        var thrown: InboxError?
        do { _ = try await inbox.fetchUnreadCount() } catch let error as InboxError { thrown = error } catch {}
        #expect(thrown == .storageFailure)
    }
}

#endif
