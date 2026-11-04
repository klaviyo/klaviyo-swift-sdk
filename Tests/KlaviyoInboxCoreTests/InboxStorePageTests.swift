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
        InboxStore(appGroup: appGroup)
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
}

#endif
