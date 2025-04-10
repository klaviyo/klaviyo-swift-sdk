//
//  UInt64+ExtTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/10/25.
//

import XCTest

class UInt64ExtensionTests: XCTestCase {
    func testNanosecondsToSeconds() {
        // 1 second
        let oneSecond: UInt64 = 1_000_000_000
        XCTAssertEqual(oneSecond.seconds, 1.0)

        // 1.5 seconds
        let oneAndHalfSeconds: UInt64 = 1_500_000_000
        XCTAssertEqual(oneAndHalfSeconds.seconds, 1.5)

        // 0.5 seconds
        let halfSecond: UInt64 = 500_000_000
        XCTAssertEqual(halfSecond.seconds, 0.5)

        // 2 seconds
        let twoSeconds: UInt64 = 2_000_000_000
        XCTAssertEqual(twoSeconds.seconds, 2.0)
    }

    func testNanosecondsToMilliseconds() {
        // 1 millisecond = 1,000,000 nanoseconds
        let oneMillisecond: UInt64 = 1_000_000
        XCTAssertEqual(oneMillisecond.milliseconds, 1.0)

        // 1.5 milliseconds
        let oneAndHalfMilliseconds: UInt64 = 1_500_000
        XCTAssertEqual(oneAndHalfMilliseconds.milliseconds, 1.5)

        // 0.5 milliseconds
        let halfMillisecond: UInt64 = 500_000
        XCTAssertEqual(halfMillisecond.milliseconds, 0.5)

        // 2 milliseconds
        let twoMilliseconds: UInt64 = 2_000_000
        XCTAssertEqual(twoMilliseconds.milliseconds, 2.0)
    }

    func testNanosecondsToMicroseconds() {
        // 1 microsecond = 1,000 nanoseconds
        let oneMicrosecond: UInt64 = 1000
        XCTAssertEqual(oneMicrosecond.microseconds, 1.0)

        // 1.5 microseconds
        let oneAndHalfMicroseconds: UInt64 = 1500
        XCTAssertEqual(oneAndHalfMicroseconds.microseconds, 1.5)

        // 0.5 microseconds
        let halfMicrosecond: UInt64 = 500
        XCTAssertEqual(halfMicrosecond.microseconds, 0.5)

        // 2 microseconds
        let twoMicroseconds: UInt64 = 2000
        XCTAssertEqual(twoMicroseconds.microseconds, 2.0)
    }

    func testNanosecondsToNanoseconds() {
        let nanos: UInt64 = 1500
        XCTAssertEqual(nanos.nanoseconds, 1500.0)
    }

    func testLargeValues() {
        // Test a large value: 1 hour = 3600 seconds = 3,600,000,000,000 nanoseconds
        let oneHour: UInt64 = 3_600_000_000_000
        XCTAssertEqual(oneHour.seconds, 3600.0)
    }

    func testSmallValues() {
        // Test very small values
        let singleNano: UInt64 = 1
        XCTAssertEqual(singleNano.seconds, 1e-9)
        XCTAssertEqual(singleNano.milliseconds, 1e-6)
        XCTAssertEqual(singleNano.microseconds, 1e-3)
        XCTAssertEqual(singleNano.nanoseconds, 1.0)
    }

    func testZeroValue() {
        let zero: UInt64 = 0
        XCTAssertEqual(zero.seconds, 0.0)
        XCTAssertEqual(zero.milliseconds, 0.0)
        XCTAssertEqual(zero.microseconds, 0.0)
        XCTAssertEqual(zero.nanoseconds, 0.0)
    }

    func testPrecision() {
        // Test that we maintain precision for small fractional values
        let preciseValue: UInt64 = 1_234_567_890
        XCTAssertEqual(preciseValue.seconds, 1.23456789)
    }
}
