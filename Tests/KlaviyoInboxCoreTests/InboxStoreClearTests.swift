//
//  InboxStoreClearTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxStoreClearTests: XCTestCase {
    private var appGroup: InboxAppGroup!
    private let company = InboxStoreFixtures.company

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    private func makeStore() -> InboxStore {
        InboxStore(appGroup: appGroup)
    }

    func testClearRemovesOnlyThatCompany() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 2, companyID: "XyZ789")
        try await store.clear(companyID: company)
        let remaining = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        XCTAssertNil(remaining)
        XCTAssertNotNil(other)
    }

    func testClearAllRemovesEverythingAndAMessageCanBeCapturedAgain() async throws {
        let store = makeStore()
        await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        await InboxStoreFixtures.capture(store, "other-1", sentAfterBase: 2, companyID: "XyZ789")
        try await store.clearAll()
        let first = try await store.message(id: "tm-1")
        let other = try await store.message(id: "other-1")
        XCTAssertNil(first)
        XCTAssertNil(other)
        let again = await InboxStoreFixtures.capture(store, "tm-1", sentAfterBase: 1)
        XCTAssertEqual(again, .captured)
    }
}
