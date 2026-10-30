//
//  DateISO8601Tests.swift
//  klaviyo-swift-sdk
//

import KlaviyoFoundation
import XCTest

final class DateISO8601Tests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_791_460_800)

    func testParsesWithAndWithoutFractionalSeconds() {
        XCTAssertEqual(Date(iso8601: "2026-10-08T12:00:00Z"), base)
        XCTAssertEqual(Date(iso8601: "2026-10-08T12:00:00.500Z"), base.addingTimeInterval(0.5))
    }

    func testParsesOffsets() {
        XCTAssertEqual(Date(iso8601: "2026-10-08T14:00:00+02:00"), base)
    }

    func testRejectsNonISOStrings() {
        for value in ["", "not a date", "1791460800", "2026-10-08"] {
            XCTAssertNil(Date(iso8601: value), "\(value) must not parse")
        }
    }

    func testFormatsInUTC() {
        XCTAssertEqual(base.iso8601String, "2026-10-08T12:00:00Z")
        XCTAssertEqual(base.addingTimeInterval(0.5).iso8601String, "2026-10-08T12:00:00.500Z")
    }

    func testFormatRoundTrips() {
        for date in [base, base.addingTimeInterval(0.25)] {
            XCTAssertEqual(Date(iso8601: date.iso8601String), date)
        }
    }
}
