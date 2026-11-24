//
//  MobileInboxClearAllTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/24/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct MobileInboxClearAllTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company
    private let otherCompany = "XyZ789"

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
    func clearAllRemovesTheCurrentCompanysMessagesAndReportsTheCount() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        // The default page hides archived messages, so archive one and look at every message below.
        try await inbox.setMessageState(.archived, for: "tm-2")
        let removed = try await inbox.clearAll()
        let page = try await inbox.fetchPage(InboxQuery(archiveFilter: .all))
        let archived = try await store.message(id: "tm-2")
        #expect(removed == 3)
        #expect(page.messages.isEmpty)
        #expect(archived == nil)
    }

    @Test
    func clearAllLeavesAnotherCompanysMessagesAlone() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 3, companyID: otherCompany)
        let removed = try await inbox.clearAll()
        let other = try await store.message(id: "other-1")
        #expect(removed == 2)
        #expect(other != nil)
    }

    @Test
    func clearAllOnAnEmptyInboxRemovesNothing() async throws {
        let (inbox, _) = makeInbox(company: company)
        let removed = try await inbox.clearAll()
        #expect(removed == 0)
    }

    @Test
    func clearAllBeforeTheSDKIsInitializedRemovesNothing() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await capture(store, count: 1)
        let removed = try await inbox.clearAll()
        let stored = try await store.message(id: "tm-1")
        #expect(removed == 0)
        #expect(stored != nil)
    }

    @Test
    func theChangeSignalFiresOncePerCallAndNotWhenNothingWasRemoved() async throws {
        let signal = RecordingInboxChangeSignal()
        let store = InboxStoreFixtures.store(appGroup: appGroup, changeSignal: signal)
        let inbox = MobileInbox(store: store, companyID: { company })
        await capture(store, count: 3)
        let baseline = signal.postCount
        try await inbox.clearAll()
        #expect(signal.postCount == baseline + 1)
        try await inbox.clearAll()
        #expect(signal.postCount == baseline + 1)
    }

    @Test
    func clearAllWaitsForThePendingReset() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 2)
        let resetRan = ResetFlag()
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: {
            await resetRan.set()
            try await store.clearAll()
        })
        let removed = try await inbox.clearAll()
        let ran = await resetRan.value
        #expect(ran)
        // The reset emptied the store first, so the call itself found nothing left to remove.
        #expect(removed == 0)
    }

    @Test
    func clearAllIsRefusedWhenThePendingResetCannotBeApplied() async throws {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        await capture(store, count: 1)
        let inbox = MobileInbox(store: store, companyID: { company }, beforeAccess: { throw InboxError.storageFailure })
        await #expect(throws: InboxError.storageFailure) { try await inbox.clearAll() }
        let stored = try await store.message(id: "tm-1")
        #expect(stored != nil)
    }

    @Test
    func aStoreThatCannotBeReachedFailsWithStorageFailure() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let inbox = MobileInbox(store: InboxStoreFixtures.store(appGroup: unreachable), companyID: { company })
        await #expect(throws: InboxError.storageFailure) { try await inbox.clearAll() }
    }

    @Test
    func aCaptureRacingClearAllIsNeverLost() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 3)
        async let removedCount = inbox.clearAll()
        async let result = InboxStoreFixtures.capture(store, "tm-racing", sentAfterBase: 10)
        let removed = try await removedCount
        let captured = await result
        let racing = try await store.message(id: "tm-racing")
        #expect(captured == .captured)
        // The capture either landed before the clear (and was removed with it) or after (and survives).
        #expect(racing == nil ? removed == 4 : removed == 3)
        // Once the race is over, a further capture is stored: the clear left nothing behind that blocks it.
        let after = await InboxStoreFixtures.capture(store, "tm-after", sentAfterBase: 11)
        let stored = try await store.message(id: "tm-after")
        #expect(after == .captured)
        #expect(stored != nil)
    }

    @Test
    func resetProfileStillEmptiesEveryCompany() async throws {
        let (inbox, store) = makeInbox(company: company)
        await capture(store, count: 2)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 3, companyID: otherCompany)
        // The reset path clears through the store's every-company operation, not the public clearAll().
        try await store.clearAll()
        let mine = try await inbox.fetchPage()
        let other = try await store.message(id: "other-1")
        #expect(mine.messages.isEmpty)
        #expect(other == nil)
    }
}

private actor ResetFlag {
    private(set) var value = false

    func set() {
        value = true
    }
}

#endif
