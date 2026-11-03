//
//  InboxStoreTests.swift
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
struct InboxStoreTests {
    private let appGroup = InboxStoreFixtures.temporaryAppGroup()
    private let company = InboxStoreFixtures.company

    private func makeStore(maxMessages: Int = InboxStore.defaultMaxMessages) -> InboxStore {
        InboxStore(appGroup: appGroup, maxMessages: maxMessages)
    }

    @Test
    func freshTransmissionIDIsCaptured() async {
        let result = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(result == .captured)
    }

    @Test
    func replayOnTheSameStoreIsADuplicate() async {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let replay = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(replay == .duplicate)
    }

    @Test
    func replayFromASecondStoreOnTheSameFileIsADuplicate() async {
        _ = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let replay = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        #expect(replay == .duplicate)
    }

    @Test
    func aDifferentTransmissionIDStaysDistinct() async {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let other = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        #expect(other == .captured)
    }

    @Test
    func theSameTransmissionIDUnderAnotherCompanyIsADuplicate() async {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let other = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: "XyZ789")
        #expect(other == .duplicate)
    }

    @Test
    func everyRecordFieldSurvivesAWriteAndRead() async throws {
        let store = makeStore()
        let record = InboxStoreFixtures.record(tm: "tm-1", sentAt: Date(timeIntervalSince1970: 1_799_999_000))
        _ = await store.capture(record, companyID: company)
        let stored = try await store.message(id: "tm-1")
        #expect(stored?.id == "tm-1")
        #expect(stored?.record == record)
        #expect(stored?.isRead == false)
        #expect(stored?.isArchived == false)
    }

    @Test
    func unknownIDReadsAsNil() async throws {
        let stored = try await makeStore().message(id: "missing")
        #expect(stored == nil)
    }

    @Test
    func storeSurvivesBeingReopened() async throws {
        _ = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let stored = try await makeStore().message(id: "tm-1")
        #expect(stored?.record.attribution.transmissionID == "tm-1")
    }
}

#endif
