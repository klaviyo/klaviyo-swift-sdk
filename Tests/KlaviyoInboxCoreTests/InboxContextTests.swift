//
//  InboxContextTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class InboxContextTests: XCTestCase {
    private var appGroup: InboxAppGroup!

    override func setUp() {
        super.setUp()
        appGroup = InboxStoreFixtures.temporaryAppGroup()
    }

    private func contextFile() throws -> URL {
        let directory = try XCTUnwrap(appGroup.inboxDirectory())
        return directory.appendingPathComponent(InboxContext.fileName)
    }

    private func writeRaw(_ json: String) throws {
        try Data(json.utf8).write(to: contextFile())
    }

    func testWrittenKeyReadsBack() {
        XCTAssertEqual(InboxContext.write(companyID: "AbC123", appGroup: appGroup), .written)
        XCTAssertEqual(InboxContext.read(appGroup: appGroup), InboxContext(companyID: "AbC123"))
    }

    func testWritingTheSameKeyAgainLeavesTheFileAlone() {
        XCTAssertEqual(InboxContext.write(companyID: "AbC123", appGroup: appGroup), .written)
        XCTAssertEqual(InboxContext.write(companyID: "AbC123", appGroup: appGroup), .unchanged)
    }

    func testADifferentKeyReplacesTheFile() {
        _ = InboxContext.write(companyID: "AbC123", appGroup: appGroup)
        XCTAssertEqual(InboxContext.write(companyID: "XyZ789", appGroup: appGroup), .written)
        XCTAssertEqual(InboxContext.read(appGroup: appGroup)?.companyID, "XyZ789")
    }

    func testEmptyKeyIsNeverWritten() {
        XCTAssertEqual(InboxContext.write(companyID: "", appGroup: appGroup), .unavailable)
        XCTAssertNil(InboxContext.read(appGroup: appGroup))
    }

    func testUnresolvedAppGroupIsUnavailable() {
        let noIdentifier = InboxAppGroup(identifier: { nil }, containerURL: { _ in URL(fileURLWithPath: "/tmp") })
        let noContainer = InboxAppGroup(identifier: { "group.test" }, containerURL: { _ in nil })
        XCTAssertEqual(InboxContext.write(companyID: "AbC123", appGroup: noIdentifier), .unavailable)
        XCTAssertEqual(InboxContext.write(companyID: "AbC123", appGroup: noContainer), .unavailable)
        XCTAssertNil(InboxContext.read(appGroup: noIdentifier))
        XCTAssertNil(InboxContext.read(appGroup: noContainer))
    }

    func testMissingFileReadsAsNil() {
        XCTAssertNil(InboxContext.read(appGroup: appGroup))
    }

    func testTruncatedFileReadsAsNil() throws {
        try writeRaw("{")
        XCTAssertNil(InboxContext.read(appGroup: appGroup))
    }

    func testNewerSchemaVersionReadsAsNil() throws {
        try writeRaw(#"{"schemaVersion": 2, "companyID": "AbC123"}"#)
        XCTAssertNil(InboxContext.read(appGroup: appGroup))
    }

    func testEmptyCompanyIDReadsAsNil() throws {
        try writeRaw(#"{"schemaVersion": 1, "companyID": ""}"#)
        XCTAssertNil(InboxContext.read(appGroup: appGroup))
    }

    func testCorruptFileIsReplacedByTheNextWrite() throws {
        try writeRaw("not json")
        XCTAssertEqual(InboxContext.write(companyID: "AbC123", appGroup: appGroup), .written)
        XCTAssertEqual(InboxContext.read(appGroup: appGroup)?.companyID, "AbC123")
    }
}
