//
//  MobileInboxConfigTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoCore
import KlaviyoInbox
import KlaviyoInboxCore
import KlaviyoInboxTestSupport
import XCTest

final class MobileInboxConfigTests: XCTestCase {
    private var logs: InboxLogRecorder!

    override func setUp() {
        super.setUp()
        logs = InboxLogRecorder()
    }

    override func tearDown() {
        logs = nil
        super.tearDown()
    }

    func testDefaultRetentionIs100() {
        XCTAssertEqual(MobileInboxConfig.defaultLocalRetentionLimit, 100)
        let config = MobileInboxConfig()
        XCTAssertEqual(config.localRetentionLimit, 100)
        XCTAssertTrue(logs.warnings.isEmpty)
    }

    func testInRangeLimitIsKeptWithoutWarning() {
        for limit in [1, 20, 500] {
            let config = MobileInboxConfig(localRetentionLimit: limit)
            XCTAssertEqual(config.localRetentionLimit, limit)
        }
        XCTAssertTrue(logs.warnings.isEmpty)
    }

    func testOutOfRangeLimitIsClampedWithWarning() {
        for (requested, expected) in [(0, 1), (-3, 1), (501, 500)] {
            let config = MobileInboxConfig(localRetentionLimit: requested)
            XCTAssertEqual(config.localRetentionLimit, expected)
        }
        XCTAssertEqual(logs.warnings.count, 3)
    }

    func testEquatable() {
        XCTAssertEqual(
            MobileInboxConfig(localRetentionLimit: 5),
            MobileInboxConfig(localRetentionLimit: 5)
        )
        XCTAssertNotEqual(
            MobileInboxConfig(localRetentionLimit: 5),
            MobileInboxConfig(localRetentionLimit: 6)
        )
    }

    func testClampWarningFollowsTheSDKWideLoggingSwitch() {
        KlaviyoLogConfig.shared.isLoggingEnabled = false
        defer { KlaviyoLogConfig.shared.isLoggingEnabled = true }
        _ = MobileInboxConfig(localRetentionLimit: 9999)
        XCTAssertTrue(logs.warnings.isEmpty, "logging disabled must silence the clamp warning")
    }
}
