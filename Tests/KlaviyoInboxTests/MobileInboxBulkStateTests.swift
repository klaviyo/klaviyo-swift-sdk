//
//  MobileInboxBulkStateTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/23/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct MobileInboxBulkStateTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeInbox(company: String?) -> (inbox: MobileInbox, store: InboxStore) {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        return (MobileInbox(store: store, companyID: { company }), store)
    }

    private func capture(_ store: InboxStore, count: Int) async {
        for index in 1...count {
            await InboxStoreFixtures.capture(store, "tm-\(index)", sentAfterBase: TimeInterval(index))
        }
    }

    @Test
    func aFilterDefaultsToTheMessagesADefaultQueryReturns() {
        let filter = InboxFilter()
        #expect(filter.readFilter == InboxQuery().readFilter)
        #expect(filter.archiveFilter == InboxQuery().archiveFilter)
    }

    @Test
    func markingAllReadChangesTheCountAndTheNextFetch() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        try await inbox.setMessageState(.read, for: "tm-1")
        let changed = try await inbox.setMessageState(.read)
        let unread = try await inbox.fetchUnreadCount()
        let page = try await inbox.fetchPage()
        #expect(changed == 2)
        #expect(unread == 0)
        #expect(page.messages.map(\.isRead) == [true, true, true])
    }

    @Test
    func theDefaultFilterLeavesArchivedMessagesAlone() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        try await inbox.setMessageState(.archived, for: "tm-1")
        let changed = try await inbox.setMessageState(.read)
        let archived = try await store.message(id: "tm-1")
        #expect(changed == 1)
        #expect(archived?.isRead == false)
    }

    @Test
    func unarchivingWithTheDefaultFilterMatchesNothing() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        try await inbox.setMessageState(.archived, for: "tm-1")
        let changed = try await inbox.setMessageState(.unarchived)
        let stored = try await store.message(id: "tm-1")
        #expect(changed == 0)
        #expect(stored?.isArchived == true)
    }

    @Test
    func unarchivingWithTheArchivedFilterRestoresThem() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        try await inbox.setMessageState(.archived, for: "tm-1")
        try await inbox.setMessageState(.archived, for: "tm-2")
        let changed = try await inbox.setMessageState(.unarchived, matching: InboxFilter(archiveFilter: .archived))
        let page = try await inbox.fetchPage()
        #expect(changed == 2)
        #expect(page.messages.count == 3)
    }

    @Test
    func theReadFilterNarrowsWhatChanges() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        try await inbox.setMessageState(.read, for: "tm-1")
        let changed = try await inbox.setMessageState(.unread, matching: InboxFilter(readFilter: .read))
        let unread = try await inbox.fetchUnreadCount()
        #expect(changed == 1)
        #expect(unread == 3)
    }

    @Test
    func anotherCompanysMessagesAreUntouched() async throws {
        let (inbox, store) = makeInbox(company: company)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2, companyID: "XyZ789")
        let changed = try await inbox.setMessageState(.read, matching: InboxFilter(archiveFilter: .all))
        let other = try await store.message(id: "tm-2")
        #expect(changed == 1)
        #expect(other?.isRead == false)
    }

    @Test
    func changingBeforeTheSDKIsInitializedChangesNothing() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await capture(store, count: 2)
        let changed = try await inbox.setMessageState(.read)
        let stored = try await store.message(id: "tm-1")
        #expect(changed == 0)
        #expect(stored?.isRead == false)
    }

    @Test
    func theChangeSignalFiresOncePerCallAndNotWhenNothingChanged() async throws {
        let signal = RecordingInboxChangeSignal()
        let store = InboxStoreFixtures.store(appGroup: appGroup, changeSignal: signal)
        let inbox = MobileInbox(store: store, companyID: { company })
        await capture(store, count: 3)
        let baseline = signal.postCount
        try await inbox.setMessageState(.read)
        #expect(signal.postCount == baseline + 1)
        try await inbox.setMessageState(.read)
        #expect(signal.postCount == baseline + 1)
    }

    @Test
    func aBulkChangeWaitsForThePendingReset() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 2)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { try await store.clearAll() })
        let changed = try await inbox.setMessageState(.read)
        #expect(changed == 0)
    }

    @Test
    func aBulkChangeIsRefusedWhenThePendingResetCannotBeApplied() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 2)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { throw InboxError.storageFailure })
        await #expect(throws: InboxError.storageFailure) { try await inbox.setMessageState(.read) }
        let stored = try await store.message(id: "tm-1")
        #expect(stored?.isRead == false)
    }

    @Test
    func aStoreThatCannotBeReachedFailsWithStorageFailure() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let inbox = MobileInbox(store: InboxStoreFixtures.store(appGroup: unreachable), companyID: { company })
        await #expect(throws: InboxError.storageFailure) { try await inbox.setMessageState(.read) }
    }
}

#endif
