//
//  InboxPayloadTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/8/26.
//

import Foundation
import KlaviyoInboxCore
#if canImport(Testing)
import Testing

@Suite
struct InboxPayloadTests {
    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func stringAcceptsNumbersAndRejectsNullAndContainers() {
        #expect(InboxPayload.string("x") == "x")
        #expect(InboxPayload.string(42) == "42")
        #expect(InboxPayload.string(NSNull()) == nil)
        #expect(InboxPayload.string(["a"]) == nil)
        #expect(InboxPayload.string(nil) == nil)
    }

    @Test
    func stringifiedHandlesNestedValuesAndNull() {
        #expect(InboxPayload.stringified("x") == "x")
        #expect(InboxPayload.stringified(2) == "2")
        #expect(InboxPayload.stringified(["b": 1, "a": 2]) == #"{"a":2,"b":1}"#)
        #expect(InboxPayload.stringified([1, 2]) == "[1,2]")
        #expect(InboxPayload.stringified(NSNull()) == nil)
    }

    @Test
    func intAcceptsIntDoubleNumericStringAndRejectsJunk() {
        #expect(InboxPayload.int(3) == 3)
        #expect(InboxPayload.int(3.7) == 3)
        #expect(InboxPayload.int(" 5 ") == 5)
        #expect(InboxPayload.int(NSNumber(value: 9)) == 9)
        #expect(InboxPayload.int("abc") == nil)
        #expect(InboxPayload.int(Double.nan) == nil)
        #expect(InboxPayload.int(NSNull()) == nil)
    }

    @Test
    func intRejectsOutOfRangeFiniteDoublesWithoutTrapping() {
        #expect(InboxPayload.int(1e30) == nil)
        #expect(InboxPayload.int(-1e30) == nil)
        #expect(InboxPayload.int(NSNumber(value: 1e30)) == nil)
        #expect(InboxPayload.int(Double(Int.max)) == nil)
        #expect(InboxPayload.int(3) == 3)
        #expect(InboxPayload.int(3.7) == 3)
        #expect(InboxPayload.int(" 5 ") == 5)
    }

    @Test
    func boolAcceptsBoolAndZeroOne() {
        #expect(InboxPayload.bool(true) == true)
        #expect(InboxPayload.bool(1) == true)
        #expect(InboxPayload.bool(0) == false)
        #expect(InboxPayload.bool(2) == true)
        #expect(InboxPayload.bool(NSNumber(value: true)) == true)
        #expect(InboxPayload.bool("yes") == nil)
        #expect(InboxPayload.bool(nil) == nil)
    }

    @Test
    func boolRejectsNonFiniteAndOutOfRangeNumbers() {
        #expect(InboxPayload.bool(NSNumber(value: 1e30)) == nil)
        #expect(InboxPayload.bool(Double.nan) == nil)
        #expect(InboxPayload.bool(-1e30) == nil)
    }

    @Test
    func dateAcceptsISOAndEpochSecondsAndMilliseconds() {
        let base = Date(timeIntervalSince1970: 1_791_460_800)
        // ISO parsing itself is covered by `DateISO8601Tests`; this checks `date` delegates to it.
        #expect(InboxPayload.date("2026-10-08T12:00:00Z") == base)
        #expect(InboxPayload.date(1_791_460_800) == base)
        #expect(InboxPayload.date(1_791_460_800_000) == base)
        #expect(InboxPayload.date("1791460800") == base)
        #expect(InboxPayload.date("not a date") == nil)
        #expect(InboxPayload.date(nil) == nil)
    }

    @Test
    func snapshotSanitizesValuesJSONCannotRepresent() throws {
        let properties: [String: Any] = [
            "nan": Double.nan,
            "data": Data([1, 2, 3]),
            "date": Date(timeIntervalSince1970: 0),
            "null": NSNull(),
            "nested": ["list": [1, "two", Data([4])]]
        ]
        let snapshot = try json(InboxPayload.snapshot(properties))
        #expect(snapshot["data"] as? String == Data([1, 2, 3]).base64EncodedString())
        #expect(snapshot["date"] as? String == "1970-01-01T00:00:00Z")
        #expect(snapshot["nan"] is String)
        #expect(snapshot["null"] is NSNull)
        #expect(snapshot.count == 5)
    }

    @Test
    func propertiesSnapshotRemovesTopLevelDeviceToken() throws {
        let input: [String: Any] = ["tm": "t", "pt": "secret", "$flow": "F1"]
        let snapshot = try json(InboxPayload.snapshot(input))
        #expect(snapshot["pt"] == nil)
        #expect(snapshot["$flow"] as? String == "F1")
    }
}

#endif
