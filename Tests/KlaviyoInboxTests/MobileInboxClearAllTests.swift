//
//  MobileInboxClearAllTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

/// The public full clear, as a host uses it: the current company's messages only, counted, and signalled
/// once.
@Suite
struct MobileInboxClearAllTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeInbox(company: String?) -> (inbox: MobileInbox, store: InboxStore) {
        MobileInboxFixtures.inbox(appGroup: appGroup, company: company)
    }

    @Test
    func clearingAllWaitsForThePendingReset() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { try await store.clearAll() })
        let removed = try await inbox.clearAll()
        #expect(removed == 0)
    }

    @Test
    func clearingAllIsRefusedWhenThePendingResetCannotBeApplied() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { throw InboxError.storageFailure })
        await #expect(throws: InboxError.storageFailure) { try await inbox.clearAll() }
        let stored = try await store.message(id: "tm-1")
        #expect(stored != nil)
    }

    @Test
    func clearingAllRemovesOnlyTheInitializedCompanysMessagesAndCountsThem() async throws {
        let (inbox, store) = makeInbox(company: company)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 3, companyID: "XyZ789")
        try await inbox.setMessageState(.archived, for: "tm-1")
        let removed = try await inbox.clearAll()
        let page = try await inbox.fetchPage(InboxQuery(archiveFilter: .all))
        let archived = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        #expect(removed == 2)
        #expect(page.messages.isEmpty)
        #expect(archived == nil)
        #expect(other != nil)
    }

    @Test
    func clearingAllAnEmptyInboxReturnsZero() async throws {
        let (inbox, _) = makeInbox(company: company)
        let removed = try await inbox.clearAll()
        #expect(removed == 0)
    }

    @Test
    func clearingAllBeforeTheSDKIsInitializedRemovesNothing() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let removed = try await inbox.clearAll()
        let stored = try await store.message(id: "tm-1")
        #expect(removed == 0)
        #expect(stored != nil)
    }

    @Test
    func clearingAllSignalsOneChangeAndAnEmptyClearSignalsNone() async throws {
        let signal = RecordingInboxChangeSignal()
        let store = InboxStoreFixtures.store(appGroup: appGroup, changeSignal: signal)
        let inbox = MobileInbox(store: store, companyID: { company })
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2)
        let captures = signal.postCount
        let removed = try await inbox.clearAll()
        #expect(removed == 2)
        #expect(signal.postCount == captures + 1)
        let empty = try await inbox.clearAll()
        #expect(empty == 0)
        #expect(signal.postCount == captures + 1)
    }

    @Test
    func aStoreThatCannotBeReachedFailsClearingAllWithStorageFailure() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let inbox = MobileInbox(store: InboxStoreFixtures.store(appGroup: unreachable), companyID: { "AbC123" })
        var thrown: InboxError?
        do { _ = try await inbox.clearAll() } catch let error as InboxError { thrown = error } catch {}
        #expect(thrown == .storageFailure)
    }
}

#endif
