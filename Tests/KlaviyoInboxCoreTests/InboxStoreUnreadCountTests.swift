//
//  InboxStoreUnreadCountTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/16/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxStoreUnreadCountTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeStore() -> InboxStore {
        InboxStoreFixtures.store(appGroup: appGroup)
    }

    private func capture(_ store: InboxStore, _ id: String, secondsAfterBase seconds: TimeInterval) async {
        await InboxStoreFixtures.capture(store, id, sentAfterBase: seconds)
    }

    @Test
    func anEmptyInboxHasNoUnreadMessages() async throws {
        let unreadCount = try await makeStore().unreadCount(companyID: company)
        #expect(unreadCount == 0)
    }

    @Test
    func anUnreadActiveMessageIsCounted() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        let unreadCount = try await store.unreadCount(companyID: company)
        #expect(unreadCount == 1)
    }

    @Test
    func aReadMessageIsNotCounted() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        try await store.setRead(true, id: "tm-1", companyID: company)
        let unreadCount = try await store.unreadCount(companyID: company)
        #expect(unreadCount == 0)
    }

    /// An archived message is not shown in the inbox, so it does not add to the count even when unread.
    @Test
    func anArchivedMessageIsNotCounted() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let unreadCount = try await store.unreadCount(companyID: company)
        #expect(unreadCount == 0)
    }

    @Test
    func onlyUnreadActiveMessagesAreCounted() async throws {
        let store = makeStore()
        await capture(store, "unread", secondsAfterBase: 4)
        await capture(store, "read", secondsAfterBase: 3)
        await capture(store, "archived-unread", secondsAfterBase: 2)
        await capture(store, "archived-read", secondsAfterBase: 1)
        try await store.setRead(true, id: "read", companyID: company)
        try await store.setArchived(true, id: "archived-unread", companyID: company)
        try await store.setRead(true, id: "archived-read", companyID: company)
        try await store.setArchived(true, id: "archived-read", companyID: company)
        let unreadCount = try await store.unreadCount(companyID: company)
        #expect(unreadCount == 1)
    }

    @Test
    func theCountCoversOnlyTheRequestedCompany() async throws {
        let store = makeStore()
        await capture(store, "mine-1", secondsAfterBase: 1)
        await capture(store, "mine-2", secondsAfterBase: 2)
        await InboxStoreFixtures.capture(store, "theirs", sentAfterBase: 3, companyID: "XyZ789")
        let mine = try await store.unreadCount(companyID: company)
        let theirs = try await store.unreadCount(companyID: "XyZ789")
        let missing = try await store.unreadCount(companyID: "NoSuchCo")
        #expect(mine == 2)
        #expect(theirs == 1)
        #expect(missing == 0)
    }

    @Test
    func theCountFollowsAStateChange() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        try await store.setRead(true, id: "tm-1", companyID: company)
        let read = try await store.unreadCount(companyID: company)
        #expect(read == 0)
        try await store.setRead(false, id: "tm-1", companyID: company)
        let unread = try await store.unreadCount(companyID: company)
        #expect(unread == 1)
    }

    @Test
    func unarchivingAnUnreadMessageCountsItAgain() async throws {
        let store = makeStore()
        await capture(store, "tm-1", secondsAfterBase: 1)
        try await store.setArchived(true, id: "tm-1", companyID: company)
        let archived = try await store.unreadCount(companyID: company)
        #expect(archived == 0)
        try await store.setArchived(false, id: "tm-1", companyID: company)
        let unarchived = try await store.unreadCount(companyID: company)
        #expect(unarchived == 1)
    }
}

#endif
