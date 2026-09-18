//
//  KlaviyoLogConfigTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
import OSLog
import XCTest

@available(iOS 14.0, *)
final class KlaviyoLogConfigTests: XCTestCase {
    override func tearDown() {
        // Always restore default state after each test
        KlaviyoLogConfig.shared.isLoggingEnabled = true
        super.tearDown()
    }

    // MARK: - Default State

    func testDefaultIsEnabled() {
        XCTAssertTrue(KlaviyoLogConfig.shared.isLoggingEnabled)
    }

    // MARK: - Toggle Behavior

    func testDisableLogging() {
        KlaviyoLogConfig.shared.isLoggingEnabled = false
        XCTAssertFalse(KlaviyoLogConfig.shared.isLoggingEnabled)
    }

    func testReEnableLogging() {
        KlaviyoLogConfig.shared.isLoggingEnabled = false
        XCTAssertFalse(KlaviyoLogConfig.shared.isLoggingEnabled)

        KlaviyoLogConfig.shared.isLoggingEnabled = true
        XCTAssertTrue(KlaviyoLogConfig.shared.isLoggingEnabled)
    }

    // MARK: - Logger Instances

    func testLoggersReturnRealLoggerWhenEnabled() {
        KlaviyoLogConfig.shared.isLoggingEnabled = true
        XCTAssertTrue(KlaviyoLogConfig.shared.isLoggingEnabled,
                      "Logging must be enabled before testing the logger accessor")
        // Verify all logger accessors return without crashing when logging is enabled.
        _ = Logger.networking
        _ = Logger.codable
        _ = Logger.navigation
        _ = Logger.notifications
    }

    func testLoggersReturnDisabledLoggerWhenDisabled() {
        KlaviyoLogConfig.shared.isLoggingEnabled = false

        // These should all return Logger(OSLog.disabled) without crashing
        let codable = Logger.codable
        let networking = Logger.networking
        let navigation = Logger.navigation
        let notifications = Logger.notifications

        // Verify they don't crash when called
        codable.info("This should be silenced")
        networking.info("This should be silenced")
        navigation.info("This should be silenced")
        notifications.info("This should be silenced")
    }

    // MARK: - Thread Safety

    func testConcurrentAccess() {
        let iterations = 1000
        let expectation = expectation(description: "Concurrent access completes")
        expectation.expectedFulfillmentCount = iterations * 2

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for _ in 0..<iterations {
            queue.async {
                KlaviyoLogConfig.shared.isLoggingEnabled = false
                expectation.fulfill()
            }
            queue.async {
                _ = KlaviyoLogConfig.shared.isLoggingEnabled
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
    }

    func testConcurrentToggleDoesNotCrash() {
        let iterations = 500
        let expectation = expectation(description: "Concurrent toggle completes")
        expectation.expectedFulfillmentCount = iterations * 2

        let queue = DispatchQueue(label: "test.concurrent.toggle", attributes: .concurrent)

        for i in 0..<iterations {
            queue.async {
                KlaviyoLogConfig.shared.isLoggingEnabled = (i % 2 == 0)
                expectation.fulfill()
            }
            queue.async {
                // Access a logger while toggling
                _ = Logger.networking
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
    }
}
