//
//  InboxStoreTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxStoreTests: XCTestCase {
    private var appGroup: InboxAppGroup!
    private let company = InboxStoreFixtures.company

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    private func makeStore(maxMessages: Int = InboxStore.maxMessages) -> InboxStore {
        InboxStore(appGroup: appGroup, maxMessages: maxMessages)
    }

    func testFreshTransmissionIDIsCaptured() async {
        let result = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        XCTAssertEqual(result, .captured)
    }

    func testReplayOnTheSameStoreIsADuplicate() async {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let replay = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        XCTAssertEqual(replay, .duplicate)
    }

    func testReplayFromASecondStoreOnTheSameFileIsADuplicate() async {
        _ = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let replay = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        XCTAssertEqual(replay, .duplicate)
    }

    func testADifferentTransmissionIDStaysDistinct() async {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let other = await store.capture(InboxStoreFixtures.record(tm: "tm-2"), companyID: company)
        XCTAssertEqual(other, .captured)
    }

    func testTheSameTransmissionIDUnderAnotherCompanyIsADuplicate() async {
        let store = makeStore()
        _ = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let other = await store.capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: "XyZ789")
        XCTAssertEqual(other, .duplicate)
    }

    func testEveryRecordFieldSurvivesAWriteAndRead() async throws {
        let store = makeStore()
        let record = InboxStoreFixtures.record(tm: "tm-1", sentAt: Date(timeIntervalSince1970: 1_799_999_000))
        _ = await store.capture(record, companyID: company)
        let stored = try await store.message(id: "tm-1")
        XCTAssertEqual(stored?.id, "tm-1")
        XCTAssertEqual(stored?.record, record)
        XCTAssertEqual(stored?.isRead, false)
        XCTAssertEqual(stored?.isArchived, false)
    }

    func testUnknownIDReadsAsNil() async throws {
        let stored = try await makeStore().message(id: "missing")
        XCTAssertNil(stored)
    }

    func testStoreSurvivesBeingReopened() async throws {
        _ = await makeStore().capture(InboxStoreFixtures.record(tm: "tm-1"), companyID: company)
        let stored = try await makeStore().message(id: "tm-1")
        XCTAssertEqual(stored?.record.attribution.transmissionID, "tm-1")
    }
}
