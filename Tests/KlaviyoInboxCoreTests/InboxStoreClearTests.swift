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
        InboxStore(appGroup: appGroup)
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
}

#endif
