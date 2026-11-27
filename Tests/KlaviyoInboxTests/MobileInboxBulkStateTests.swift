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

    private let notArchived = InboxFilter.where(read: .all, archive: .active)

    @Test
    func aFilterCarriesTheStatesItWasBuiltWith() {
        let filter = InboxFilter.where(read: .unread, archive: .archived)
        #expect(filter.readFilter == .unread)
        #expect(filter.archiveFilter == .archived)
    }

    @Test
    func allMessagesMatchesEveryReadAndArchiveState() {
        #expect(InboxFilter.allMessages.readFilter == .all)
        #expect(InboxFilter.allMessages.archiveFilter == .all)
    }

    @Test
    func markingAllReadChangesTheCountAndTheNextFetch() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        try await inbox.setMessageState(.read, for: "tm-1")
        let changed = try await inbox.setMessageState(.read, matching: notArchived)
        let unread = try await inbox.fetchUnreadCount()
        let page = try await inbox.fetchPage()
        #expect(changed == 2)
        #expect(unread == 0)
        #expect(page.messages.map(\.isRead) == [true, true, true])
    }

    @Test
    func aFilterThatLeavesOutArchivedMessagesLeavesThemAlone() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        try await inbox.setMessageState(.archived, for: "tm-1")
        let changed = try await inbox.setMessageState(.read, matching: notArchived)
        let archived = try await store.message(id: "tm-1")
        #expect(changed == 1)
        #expect(archived?.isRead == false)
    }

    @Test
    func unarchivingWithAFilterThatLeavesOutArchivedMessagesMatchesNothing() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        try await inbox.setMessageState(.archived, for: "tm-1")
        let changed = try await inbox.setMessageState(.unarchived, matching: notArchived)
        let stored = try await store.message(id: "tm-1")
        #expect(changed == 0)
        #expect(stored?.isArchived == true)
    }

    @Test
    func unarchivingWithAllMessagesRestoresArchivedOnes() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        try await inbox.setMessageState(.archived, for: "tm-1")
        let changed = try await inbox.setMessageState(.unarchived, matching: .allMessages)
        let stored = try await store.message(id: "tm-1")
        #expect(changed == 1)
        #expect(stored?.isArchived == false)
    }

    @Test
    func unarchivingWithTheArchivedFilterRestoresThem() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        try await inbox.setMessageState(.archived, for: "tm-1")
        try await inbox.setMessageState(.archived, for: "tm-2")
        let changed = try await inbox.setMessageState(.unarchived, matching: .where(read: .all, archive: .archived))
        let page = try await inbox.fetchPage()
        #expect(changed == 2)
        #expect(page.messages.count == 3)
    }

    @Test
    func theReadFilterNarrowsWhatChanges() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        try await inbox.setMessageState(.read, for: "tm-1")
        let changed = try await inbox.setMessageState(.unread, matching: .where(read: .read, archive: .active))
        let unread = try await inbox.fetchUnreadCount()
        #expect(changed == 1)
        #expect(unread == 3)
    }

    @Test
    func anotherCompanysMessagesAreUntouched() async throws {
        let (inbox, store) = makeInbox(company: company)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2, companyID: "XyZ789")
        let changed = try await inbox.setMessageState(.read, matching: .allMessages)
        let other = try await store.message(id: "tm-2")
        #expect(changed == 1)
        #expect(other?.isRead == false)
    }

    @Test
    func changingBeforeTheSDKIsInitializedChangesNothing() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await capture(store, count: 2)
        let changed = try await inbox.setMessageState(.read, matching: notArchived)
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
        try await inbox.setMessageState(.read, matching: notArchived)
        #expect(signal.postCount == baseline + 1)
        try await inbox.setMessageState(.read, matching: notArchived)
        #expect(signal.postCount == baseline + 1)
    }

    @Test
    func aBulkChangeWaitsForThePendingReset() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 2)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { try await store.clearAll() })
        let changed = try await inbox.setMessageState(.read, matching: notArchived)
        #expect(changed == 0)
    }

    @Test
    func aBulkChangeIsRefusedWhenThePendingResetCannotBeApplied() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 2)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { throw InboxError.storageFailure })
        await #expect(throws: InboxError.storageFailure) { try await inbox.setMessageState(.read, matching: notArchived) }
        let stored = try await store.message(id: "tm-1")
        #expect(stored?.isRead == false)
    }

    @Test
    func aStoreThatCannotBeReachedFailsWithStorageFailure() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let inbox = MobileInbox(store: InboxStoreFixtures.store(appGroup: unreachable), companyID: { company })
        await #expect(throws: InboxError.storageFailure) { try await inbox.setMessageState(.read, matching: notArchived) }
    }

    // MARK: - By ID

    @Test
    func settingStateByIdsChangesOnlyThoseMessagesAndCountsThem() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        try await inbox.setMessageState(.read, for: "tm-1")
        let changed = try await inbox.setMessageState(.read, for: ["tm-1", "tm-2"])
        let unread = try await inbox.fetchUnreadCount()
        let third = try await store.message(id: "tm-3")
        #expect(changed == 1)
        #expect(unread == 1)
        #expect(third?.isRead == false)
    }

    @Test
    func singleIdAndIdListOverloadsResolveAtCallSites() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        let single: Bool = try await inbox.setMessageState(.read, for: "tm-1")
        let literal: Int = try await inbox.setMessageState(.read, for: ["tm-2"])
        let ids = ["tm-1"]
        let list: Int = try await inbox.setMessageState(.archived, for: ids)
        let empty: Int = try await inbox.setMessageState(.archived, for: [])
        #expect(single)
        #expect(literal == 1)
        #expect(list == 1)
        #expect(empty == 0)
    }

    @Test
    func unknownAndOtherCompanyIdsAndDuplicatesAreHandledByIds() async throws {
        let (inbox, store) = makeInbox(company: company)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2, companyID: "XyZ789")
        let changed = try await inbox.setMessageState(.read, for: ["tm-1", "tm-1", "tm-2", "missing"])
        let other = try await store.message(id: "tm-2")
        #expect(changed == 1)
        #expect(other?.isRead == false)
    }

    @Test
    func settingStateByIdsBeforeTheSDKIsInitializedChangesNothing() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await capture(store, count: 2)
        let changed = try await inbox.setMessageState(.read, for: ["tm-1", "tm-2"])
        let stored = try await store.message(id: "tm-1")
        #expect(changed == 0)
        #expect(stored?.isRead == false)
    }

    @Test
    func anEmptyIdListReturnsZeroAndFiresNoChange() async throws {
        let signal = RecordingInboxChangeSignal()
        let store = InboxStoreFixtures.store(appGroup: appGroup, changeSignal: signal)
        let inbox = MobileInbox(store: store, companyID: { company })
        await capture(store, count: 1)
        let baseline = signal.postCount
        let changed = try await inbox.setMessageState(.read, for: [String]())
        #expect(changed == 0)
        #expect(signal.postCount == baseline)
    }

    @Test
    func theIdChangeSignalFiresOncePerCallAndNotWhenNothingChanged() async throws {
        let signal = RecordingInboxChangeSignal()
        let store = InboxStoreFixtures.store(appGroup: appGroup, changeSignal: signal)
        let inbox = MobileInbox(store: store, companyID: { company })
        await capture(store, count: 3)
        let baseline = signal.postCount
        try await inbox.setMessageState(.read, for: ["tm-1", "tm-2"])
        #expect(signal.postCount == baseline + 1)
        try await inbox.setMessageState(.read, for: ["tm-1", "tm-2"])
        #expect(signal.postCount == baseline + 1)
    }

    @Test
    func aChangeByIdsWaitsForThePendingReset() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 2)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { try await store.clearAll() })
        let changed = try await inbox.setMessageState(.read, for: ["tm-1", "tm-2"])
        #expect(changed == 0)
    }

    @Test
    func aChangeByIdsIsRefusedWhenThePendingResetCannotBeApplied() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 2)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { throw InboxError.storageFailure })
        await #expect(throws: InboxError.storageFailure) { try await inbox.setMessageState(.read, for: ["tm-1"]) }
        let stored = try await store.message(id: "tm-1")
        #expect(stored?.isRead == false)
    }

    @Test
    func aStoreThatCannotBeReachedFailsByIdsWithStorageFailure() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let inbox = MobileInbox(store: InboxStoreFixtures.store(appGroup: unreachable), companyID: { company })
        await #expect(throws: InboxError.storageFailure) { try await inbox.setMessageState(.read, for: ["tm-1"]) }
    }
}

#endif
