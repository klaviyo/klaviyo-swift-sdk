//
//  MobileInboxTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

@testable import KlaviyoInbox
import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct MobileInboxTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeInbox(company: String?) -> (inbox: MobileInbox, store: InboxStore) {
        let store = InboxStoreFixtures.store(appGroup: appGroup)
        return (MobileInbox(store: store, companyID: { company }), store)
    }

    @Test
    func aPageBeforeTheSDKIsInitializedIsEmpty() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let page = try await inbox.fetchPage()
        #expect(page.messages.isEmpty)
        #expect(page.nextCursor == nil)
    }

    private func captureMessages(_ store: InboxStore, count: Int) async {
        for index in 1...count {
            await InboxStoreFixtures.capture(store, "tm-\(index)", sentAfterBase: TimeInterval(index))
        }
    }

    @Test
    func aPageIsNewestFirstAndAnEmptyInboxIsAnEmptyPage() async throws {
        let (inbox, store) = makeInbox(company: company)
        let empty = try await inbox.fetchPage()
        await captureMessages(store, count: 3)
        let page = try await inbox.fetchPage()
        #expect(empty.messages.isEmpty)
        #expect(page.messages.map(\.id) == ["tm-3", "tm-2", "tm-1"])
        #expect(page.nextCursor == nil)
    }

    @Test
    func theNextCursorContinuesThroughEveryMessage() async throws {
        let (inbox, store) = makeInbox(company: company)
        await captureMessages(store, count: 5)
        let first = try await inbox.fetchPage(InboxQuery(pageSize: 2))
        let second = try await inbox.fetchPage(InboxQuery(pageSize: 2, cursor: first.nextCursor))
        let third = try await inbox.fetchPage(InboxQuery(pageSize: 2, cursor: second.nextCursor))
        #expect(first.messages.map(\.id) == ["tm-5", "tm-4"])
        #expect(second.messages.map(\.id) == ["tm-3", "tm-2"])
        #expect(third.messages.map(\.id) == ["tm-1"])
        #expect(third.nextCursor == nil)
    }

    @Test
    func thePageSizeIsClampedToTheAllowedRange() {
        #expect(InboxQuery().pageSize == 20)
        #expect(InboxQuery(pageSize: 0).pageSize == 1)
        #expect(InboxQuery(pageSize: -5).pageSize == 1)
        #expect(InboxQuery(pageSize: 500).pageSize == 100)
    }

    @Test
    func aMalformedCursorFailsWithInvalidCursor() async {
        let (inbox, _) = makeInbox(company: company)
        var thrown: InboxError?
        do {
            _ = try await inbox.fetchPage(InboxQuery(cursor: InboxCursor(token: "nope")))
        } catch let error as InboxError {
            thrown = error
        } catch {}
        #expect(thrown == .invalidCursor)
    }

    @Test
    func aCursorFromAnotherCompanyFailsWithInvalidCursor() async throws {
        let (other, otherStore) = makeInbox(company: "XyZ789")
        await InboxStoreFixtures.capture(otherStore, "tm-1", sentAfterBase: 1, companyID: "XyZ789")
        await InboxStoreFixtures.capture(otherStore, "tm-2", sentAfterBase: 2, companyID: "XyZ789")
        let page = try await other.fetchPage(InboxQuery(pageSize: 1))
        let (mine, _) = makeInbox(company: company)
        var thrown: InboxError?
        do {
            _ = try await mine.fetchPage(InboxQuery(cursor: page.nextCursor))
        } catch let error as InboxError {
            thrown = error
        } catch {}
        #expect(thrown == .invalidCursor)
    }

    @Test
    func aPageOnlyHoldsTheInitializedCompanysMessages() async throws {
        let (inbox, store) = makeInbox(company: company)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 2, companyID: "XyZ789")
        let page = try await inbox.fetchPage()
        #expect(page.messages.map(\.id) == ["tm-1"])
    }

    @Test
    func aPersistedKeyOnlyCountsOnceInitializeHasBegunThisLaunch() {
        #expect(MobileInbox.sessionCompanyID(isInitialized: false, apiKey: "AbC123") == nil)
        #expect(MobileInbox.sessionCompanyID(isInitialized: true, apiKey: "AbC123") == "AbC123")
        #expect(MobileInbox.sessionCompanyID(isInitialized: true, apiKey: nil) == nil)
        #expect(MobileInbox.sessionCompanyID(isInitialized: true, apiKey: "") == nil)
    }

    @Test
    func theSDKExposesTheInboxAndItReadsThisSessionsCompany() async throws {
        struct FakeSDK: KlaviyoSDKModule {}
        let inbox = FakeSDK().mobileInbox
        // Not initialized in this process, so there is no session company yet.
        let page = try await inbox.fetchPage()
        #expect(page.messages.isEmpty)
    }

    @Test
    func settingAMessageStateIsVisibleOnTheNextPage() async throws {
        let (inbox, store) = makeInbox(company: company)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        try await inbox.setMessageState(.read, for: "tm-1")
        try await inbox.setMessageState(.archived, for: "tm-1")
        let message = try await inbox.fetchPage().messages.first
        #expect(message?.isRead == true)
        #expect(message?.isArchived == true)
    }

    @Test
    func settingAStateReportsWhetherTheMessageExists() async throws {
        let (inbox, store) = makeInbox(company: company)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let first = try await inbox.setMessageState(.read, for: "tm-1")
        // Already read: nothing changes, but the message is there.
        let repeated = try await inbox.setMessageState(.read, for: "tm-1")
        let missing = try await inbox.setMessageState(.read, for: "missing")
        let page = try await inbox.fetchPage()
        #expect(first)
        #expect(repeated)
        #expect(!missing)
        #expect(page.messages.map(\.isRead) == [true])
    }

    @Test
    func settingAStateBeforeTheSDKIsInitializedChangesNothing() async throws {
        let (inbox, store) = makeInbox(company: nil)
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let exists = try await inbox.setMessageState(.read, for: "tm-1")
        let stored = try await store.message(id: "tm-1")
        #expect(!exists)
        #expect(stored?.isRead == false)
    }

    @Test
    func theChangeStreamFiresWhenTheStoreChanges() async throws {
        // One identifier for the whole test: the post and the listener must agree on the name.
        let identifier = "group.test.\(UUID().uuidString)"
        let group = InboxAppGroup(
            identifier: { identifier },
            containerURL: { [appGroup] _ in appGroup.containerURL(InboxStoreFixtures.groupIdentifier) }
        )
        let signal = DarwinInboxChangeSignal(appGroup: group)
        let store = InboxStore(appGroup: group, changeSignal: signal)
        let inbox = MobileInbox(store: store, companyID: { company }, changes: signal.changes)
        var iterator = inbox.changes.makeAsyncIterator()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let fired = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await iterator.next() != nil }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(fired)
    }

    @Test
    func aStoreThatCannotBeReachedFailsWithStorageFailure() async {
        let unreachable = InboxAppGroup(identifier: { nil }, containerURL: { _ in nil })
        let inbox = MobileInbox(store: InboxStoreFixtures.store(appGroup: unreachable), companyID: { "AbC123" })
        var thrown: InboxError?
        do { _ = try await inbox.fetchPage() } catch let error as InboxError { thrown = error } catch {}
        #expect(thrown == .storageFailure)
    }
}

#endif
