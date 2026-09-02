//
//  BadgeManagerTests.swift
//
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Foundation
import XCTest

@MainActor
class BadgeManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BadgeManager.resetToProduction()
    }

    override func tearDown() {
        BadgeManager.resetToProduction()
        super.tearDown()
    }

    // MARK: - setBadgeCount

    func testSetBadgeCount_noAppGroup_isNoOp() async {
        // When no app group is configured, setBadgeCount must not call
        // setNativeBadge or write to UserDefaults.
        BadgeManager.dependencies.appGroupUserDefaults = { nil }

        var nativeBadgeSet = false
        BadgeManager.dependencies.setNativeBadge = { _ in nativeBadgeSet = true }

        await BadgeManager.setBadgeCount(5)

        XCTAssertFalse(nativeBadgeSet, "setNativeBadge must not be called when no app group is configured")
    }

    func testSetBadgeCount_withAppGroup_setsNativeBadgeAndPersists() async {
        let suiteName = "com.klaviyo.badge.test.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        BadgeManager.dependencies.appGroupUserDefaults = { userDefaults }

        var capturedCount: Int?
        BadgeManager.dependencies.setNativeBadge = { count in capturedCount = count }

        await BadgeManager.setBadgeCount(3)

        XCTAssertEqual(capturedCount, 3, "setNativeBadge should be called with the correct count")
        XCTAssertEqual(userDefaults.integer(forKey: BadgeManager.badgeCountKey), 3,
                       "badgeCount should be persisted to app-group UserDefaults")

        // Cleanup
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testSetBadgeCount_withSpy_callsSpyInsteadOfProduction() async {
        var spyCount: Int?
        BadgeManager.setBadgeCountSpy = { spyCount = $0 }

        var nativeBadgeSet = false
        BadgeManager.dependencies.setNativeBadge = { _ in nativeBadgeSet = true }

        await BadgeManager.setBadgeCount(7)

        XCTAssertEqual(spyCount, 7, "spy should receive the count")
        XCTAssertFalse(nativeBadgeSet, "production path must be bypassed when spy is installed")
    }

    // MARK: - syncBadgeCount

    func testSyncBadgeCount_noAppGroup_isNoOp() {
        BadgeManager.dependencies.appGroupUserDefaults = { nil }
        BadgeManager.dependencies.currentNativeBadge = { 99 }

        // Should complete without writing anything — no crash or side effect.
        BadgeManager.syncBadgeCount()
        // No assertion needed beyond "it didn't crash."
    }

    func testSyncBadgeCount_withAppGroup_persistsCurrentBadge() {
        let suiteName = "com.klaviyo.sync.test.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        BadgeManager.dependencies.appGroupUserDefaults = { userDefaults }
        BadgeManager.dependencies.currentNativeBadge = { 42 }

        BadgeManager.syncBadgeCount()

        XCTAssertEqual(userDefaults.integer(forKey: BadgeManager.badgeCountKey), 42,
                       "syncBadgeCount should persist the current native badge value")

        // Cleanup
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testSyncBadgeCount_withSpy_callsSpyInsteadOfProduction() {
        var syncCalled = false
        BadgeManager.syncBadgeCountSpy = { syncCalled = true }

        var nativeBadgeRead = false
        BadgeManager.dependencies.currentNativeBadge = { nativeBadgeRead = true; return 0 }

        BadgeManager.syncBadgeCount()

        XCTAssertTrue(syncCalled, "spy should be invoked")
        XCTAssertFalse(nativeBadgeRead, "production path must be bypassed when spy is installed")
    }

    // MARK: - resetToProduction

    func testResetToProduction_clearsBothSpies() async {
        BadgeManager.setBadgeCountSpy = { _ in }
        BadgeManager.syncBadgeCountSpy = {}

        BadgeManager.resetToProduction()

        XCTAssertNil(BadgeManager.setBadgeCountSpy)
        XCTAssertNil(BadgeManager.syncBadgeCountSpy)
    }

    // MARK: - KlaviyoSDK.setBadgeCount facade gate

    func testFacadeSetBadgeCount_whenUninitialized_appliesWithoutWarning() async {
        // Setting the badge is a local operation with no initialization dependency,
        // so it must apply even when the SDK is uninitialized and never emit an
        // initialization warning. This also guards against re-introducing a gate
        // that would race the async `initialize(with:)`.
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        klaviyoSwiftEnvironment.state = { KlaviyoState(requestsInFlight: []) } // .uninitialized

        var warningEmitted = false
        environment.emitDeveloperWarning = { _ in warningEmitted = true }

        let badgeExpectation = expectation(description: "BadgeManager called while uninitialized")
        BadgeManager.setBadgeCountSpy = { count in
            XCTAssertEqual(count, 5)
            badgeExpectation.fulfill()
        }

        KlaviyoSDK().setBadgeCount(5)

        await fulfillment(of: [badgeExpectation], timeout: 2)
        XCTAssertFalse(warningEmitted, "setBadgeCount must not emit an initialization warning")
    }

    func testFacadeSetBadgeCount_whenInitialized_callsBadgeManager() async {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        klaviyoSwiftEnvironment.state = { INITIALIZED_TEST_STATE() }

        let badgeExpectation = expectation(description: "BadgeManager called with correct count")
        BadgeManager.setBadgeCountSpy = { count in
            XCTAssertEqual(count, 3)
            badgeExpectation.fulfill()
        }

        KlaviyoSDK().setBadgeCount(3)

        await fulfillment(of: [badgeExpectation], timeout: 2)
    }
}
