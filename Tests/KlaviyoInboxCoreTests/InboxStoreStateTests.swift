//
//  InboxStoreStateTests.swift
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
struct InboxStoreStateTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeStoreWithMessage(_ id: String = "tm-1") async -> InboxStore {
        let store = InboxStore(appGroup: appGroup)
        await InboxStoreFixtures.capture(store, id, sentAfterBase: 1)
        return store
    }

    @Test
    func markingAMessageReadSetsItReadAndReportsAChange() async throws {
        let store = await makeStoreWithMessage()
        let changed = try await store.setState(.read, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(changed)
        #expect(message?.isRead == true)
    }

    @Test
    func markingAReadMessageUnreadClearsItsReadState() async throws {
        let store = await makeStoreWithMessage()
        try await store.setState(.read, id: "tm-1", companyID: company)
        let changed = try await store.setState(.unread, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(changed)
        #expect(message?.isRead == false)
    }

    @Test
    func archivingAndUnarchivingToggleOnlyTheArchivedState() async throws {
        let store = await makeStoreWithMessage()
        try await store.setState(.archived, id: "tm-1", companyID: company)
        let archived = try await store.message(id: "tm-1")
        try await store.setState(.unarchived, id: "tm-1", companyID: company)
        let unarchived = try await store.message(id: "tm-1")
        #expect(archived?.isArchived == true)
        #expect(archived?.isRead == false)
        #expect(unarchived?.isArchived == false)
    }

    @Test
    func readAndArchivedAreIndependent() async throws {
        let store = await makeStoreWithMessage()
        try await store.setState(.read, id: "tm-1", companyID: company)
        try await store.setState(.archived, id: "tm-1", companyID: company)
        try await store.setState(.unread, id: "tm-1", companyID: company)
        let message = try await store.message(id: "tm-1")
        #expect(message?.isRead == false)
        #expect(message?.isArchived == true)
    }

    @Test
    func applyingAStateTheMessageAlreadyHasChangesNothing() async throws {
        let store = await makeStoreWithMessage()
        let unreadAgain = try await store.setState(.unread, id: "tm-1", companyID: company)
        let unarchivedAgain = try await store.setState(.unarchived, id: "tm-1", companyID: company)
        try await store.setState(.read, id: "tm-1", companyID: company)
        let readAgain = try await store.setState(.read, id: "tm-1", companyID: company)
        #expect(!unreadAgain)
        #expect(!unarchivedAgain)
        #expect(!readAgain)
    }

    @Test
    func anUnknownMessageChangesNothing() async throws {
        let store = await makeStoreWithMessage()
        let changed = try await store.setState(.read, id: "missing", companyID: company)
        #expect(!changed)
    }

    @Test
    func aStateChangeIsVisibleToAnotherStoreOnTheSameAppGroup() async throws {
        let store = await makeStoreWithMessage()
        try await store.setState(.archived, id: "tm-1", companyID: company)
        let other = InboxStore(appGroup: appGroup)
        let message = try await other.message(id: "tm-1")
        #expect(message?.isArchived == true)
    }

    @Test
    func replayingACapturedPushKeepsTheMessageState() async throws {
        let store = await makeStoreWithMessage()
        try await store.setState(.read, id: "tm-1", companyID: company)
        try await store.setState(.archived, id: "tm-1", companyID: company)
        let replay = await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        let message = try await store.message(id: "tm-1")
        #expect(replay == .duplicate)
        #expect(message?.isRead == true)
        #expect(message?.isArchived == true)
    }

    @Test
    func aMessageOfAnotherCompanyIsLeftAlone() async throws {
        let store = await makeStoreWithMessage()
        let changed = try await store.setState(.read, id: "tm-1", companyID: "XyZ789")
        let message = try await store.message(id: "tm-1")
        #expect(!changed)
        #expect(message?.isRead == false)
    }
}

#endif
