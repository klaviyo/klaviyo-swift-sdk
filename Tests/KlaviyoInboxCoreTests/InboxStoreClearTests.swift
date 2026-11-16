//
//  InboxStoreClearTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
#if canImport(Testing)
import Testing

@Suite
struct InboxStoreClearTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeStore() -> InboxStore {
        InboxStoreFixtures.store(appGroup: appGroup)
    }

    @Test
    func clearRemovesOnlyThatCompany() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 2, companyID: "XyZ789")
        try await store.clear(companyID: company)
        let remaining = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        #expect(remaining == nil)
        #expect(other != nil)
    }

    @Test
    func clearAllRemovesEverythingAndAMessageCanBeCapturedAgain() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 2, companyID: "XyZ789")
        try await store.clearAll()
        let first = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        #expect(first == nil)
        #expect(other == nil)
        let again = await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        #expect(again == .captured)
    }

    @Test
    func clearByIdsRemovesOnlyThoseMessagesAndCountsThem() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "tm-2", sentAfterBase: 2)
        await InboxStoreFixtures.capture(store, "tm-3", sentAfterBase: 3)
        let removed = try await store.clear(ids: ["tm-1", "tm-3", "missing"], companyID: company)
        #expect(removed == 2)
        #expect(try await store.message(id: "tm-1") == nil)
        #expect(try await store.message(id: "tm-2") != nil)
        #expect(try await store.message(id: "tm-3") == nil)
    }

    @Test
    func clearByIdsIgnoresAnotherCompanysMessage() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 1, companyID: "XyZ789")
        let removed = try await store.clear(ids: ["other-1"], companyID: company)
        #expect(removed == 0)
        #expect(try await store.message(id: "other-1") != nil)
    }

    @Test
    func clearByNoIdsRemovesNothing() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        #expect(try await store.clear(ids: [], companyID: company) == 0)
        #expect(try await store.message(id: "tm-1") != nil)
    }
}

#endif
