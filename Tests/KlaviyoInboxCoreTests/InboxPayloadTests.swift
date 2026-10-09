//
//  InboxPayloadTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
import XCTest

final class InboxPayloadTests: XCTestCase {
    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDictionaryAcceptsEveryBridgedForm() {
        let swift: [String: Any] = ["a": 1]
        let anyHashable: [AnyHashable: Any] = ["a": 1, 2: "skipped"]
        let objc = NSDictionary(dictionary: ["a": 1])
        XCTAssertEqual(InboxPayload.dictionary(swift)?["a"] as? Int, 1)
        XCTAssertEqual(InboxPayload.dictionary(anyHashable)?["a"] as? Int, 1)
        XCTAssertEqual(InboxPayload.dictionary(anyHashable)?.count, 1, "non-string keys are skipped")
        XCTAssertEqual(InboxPayload.dictionary(objc)?["a"] as? Int, 1)
        XCTAssertNil(InboxPayload.dictionary("not a dictionary"))
        XCTAssertNil(InboxPayload.dictionary(nil))
    }

    func testStringAcceptsNumbersAndRejectsNullAndContainers() {
        XCTAssertEqual(InboxPayload.string("x"), "x")
        XCTAssertEqual(InboxPayload.string(42), "42")
        XCTAssertNil(InboxPayload.string(NSNull()))
        XCTAssertNil(InboxPayload.string(["a"]))
        XCTAssertNil(InboxPayload.string(nil))
    }

    func testStringifiedHandlesNestedValuesAndNull() {
        XCTAssertEqual(InboxPayload.stringified("x"), "x")
        XCTAssertEqual(InboxPayload.stringified(2), "2")
        XCTAssertEqual(InboxPayload.stringified(["b": 1, "a": 2]), #"{"a":2,"b":1}"#)
        XCTAssertEqual(InboxPayload.stringified([1, 2]), "[1,2]")
        XCTAssertNil(InboxPayload.stringified(NSNull()))
    }

    func testIntAcceptsIntDoubleNumericStringAndRejectsJunk() {
        XCTAssertEqual(InboxPayload.int(3), 3)
        XCTAssertEqual(InboxPayload.int(3.7), 3)
        XCTAssertEqual(InboxPayload.int(" 5 "), 5)
        XCTAssertEqual(InboxPayload.int(NSNumber(value: 9)), 9)
        XCTAssertNil(InboxPayload.int("abc"))
        XCTAssertNil(InboxPayload.int(Double.nan))
        XCTAssertNil(InboxPayload.int(NSNull()))
    }

    func testIntRejectsOutOfRangeFiniteDoublesWithoutTrapping() {
        XCTAssertNil(InboxPayload.int(1e30))
        XCTAssertNil(InboxPayload.int(-1e30))
        XCTAssertNil(InboxPayload.int(NSNumber(value: 1e30)))
        XCTAssertNil(InboxPayload.int(Double(Int.max)))
        XCTAssertEqual(InboxPayload.int(3), 3)
        XCTAssertEqual(InboxPayload.int(3.7), 3)
        XCTAssertEqual(InboxPayload.int(" 5 "), 5)
    }

    func testBoolAcceptsBoolAndZeroOne() {
        XCTAssertEqual(InboxPayload.bool(true), true)
        XCTAssertEqual(InboxPayload.bool(1), true)
        XCTAssertEqual(InboxPayload.bool(0), false)
        XCTAssertEqual(InboxPayload.bool(2), true)
        XCTAssertEqual(InboxPayload.bool(NSNumber(value: true)), true)
        XCTAssertNil(InboxPayload.bool("yes"))
        XCTAssertNil(InboxPayload.bool(nil))
    }

    func testBoolRejectsNonFiniteAndOutOfRangeNumbers() {
        XCTAssertNil(InboxPayload.bool(NSNumber(value: 1e30)))
        XCTAssertNil(InboxPayload.bool(Double.nan))
        XCTAssertNil(InboxPayload.bool(-1e30))
    }

    func testDateAcceptsISOWithAndWithoutFractionsAndEpochSecondsAndMilliseconds() {
        let base = Date(timeIntervalSince1970: 1_791_460_800)
        XCTAssertEqual(InboxPayload.date("2026-10-08T12:00:00Z"), base)
        XCTAssertEqual(InboxPayload.date("2026-10-08T12:00:00.500Z"), base.addingTimeInterval(0.5))
        XCTAssertEqual(InboxPayload.date(1_791_460_800), base)
        XCTAssertEqual(InboxPayload.date(1_791_460_800_000), base)
        XCTAssertEqual(InboxPayload.date("1791460800"), base)
        XCTAssertNil(InboxPayload.date("not a date"))
        XCTAssertNil(InboxPayload.date(nil))
    }

    func testSnapshotRemovesDeviceTokenOnlyFromKlaviyoMetadata() throws {
        let userInfo: [AnyHashable: Any] = [
            "pt": "top-level stays",
            "body": ["_k": ["tm": "t", "pt": "secret-token"], "other": ["pt": "nested stays"]]
        ]
        let snapshot = try json(InboxPayload.snapshot(userInfo))
        let body = try XCTUnwrap(snapshot["body"] as? [String: Any])
        let metadata = try XCTUnwrap(body["_k"] as? [String: Any])
        XCTAssertNil(metadata["pt"])
        XCTAssertEqual(metadata["tm"] as? String, "t")
        XCTAssertEqual(snapshot["pt"] as? String, "top-level stays")
        XCTAssertNotNil((body["other"] as? [String: Any])?["pt"])
    }

    func testSnapshotSanitizesValuesJSONCannotRepresent() throws {
        let userInfo: [AnyHashable: Any] = [
            "nan": Double.nan,
            "data": Data([1, 2, 3]),
            "date": Date(timeIntervalSince1970: 0),
            "null": NSNull(),
            "nested": ["list": [1, "two", Data([4])]],
            5: "non-string key"
        ]
        let snapshot = try json(InboxPayload.snapshot(userInfo))
        XCTAssertEqual(snapshot["data"] as? String, Data([1, 2, 3]).base64EncodedString())
        XCTAssertEqual(snapshot["date"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertTrue(snapshot["nan"] is String)
        XCTAssertTrue(snapshot["null"] is NSNull)
        XCTAssertNil(snapshot["5"], "non-string keys are skipped")
        XCTAssertEqual(snapshot.count, 5)
    }

    func testPropertiesSnapshotRemovesTopLevelDeviceToken() throws {
        let input: [String: Any] = ["tm": "t", "pt": "secret", "$flow": "F1"]
        let snapshot = try json(InboxPayload.snapshot(input))
        XCTAssertNil(snapshot["pt"])
        XCTAssertEqual(snapshot["$flow"] as? String, "F1")
    }
}
