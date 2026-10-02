//
//  InboxLimitsTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoInboxCore
import XCTest

final class InboxLimitsTests: XCTestCase {
    func testClampsToRange() {
        XCTAssertEqual(InboxLimits.clampedRetention(Int.min), 1)
        XCTAssertEqual(InboxLimits.clampedRetention(-5), 1)
        XCTAssertEqual(InboxLimits.clampedRetention(0), 1)
        XCTAssertEqual(InboxLimits.clampedRetention(1), 1)
        XCTAssertEqual(InboxLimits.clampedRetention(100), 100)
        XCTAssertEqual(InboxLimits.clampedRetention(500), 500)
        XCTAssertEqual(InboxLimits.clampedRetention(501), 500)
        XCTAssertEqual(InboxLimits.clampedRetention(Int.max), 500)
    }

    func testDefaultIsInsideRange() {
        XCTAssertEqual(InboxLimits.defaultRetention, 100)
        XCTAssertTrue(InboxLimits.retentionRange.contains(InboxLimits.defaultRetention))
    }
}
