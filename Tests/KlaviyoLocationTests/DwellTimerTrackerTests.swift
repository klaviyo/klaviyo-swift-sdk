//
//  DwellTimerTrackerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

@testable import KlaviyoLocation
import Foundation
import KlaviyoCore
import KlaviyoSwift
import XCTest

final class DwellTimerTrackerTests: XCTestCase {
    var tracker: DwellTimerTracker!
    var mockDate: Date!
    let baseTime: TimeInterval = 1_700_000_000 // Fixed base time for testing
    let testCompanyId = "test-company-id"

    override func setUp() {
        super.setUp()

        // Set up mock date that we can control
        mockDate = Date(timeIntervalSince1970: baseTime)

        // Set up test environment with controlled date
        environment = KlaviyoEnvironment.test()
        environment.date = { [weak self] in
            self?.mockDate ?? Date()
        }

        tracker = DwellTimerTracker()

        // Clean up any existing timer data
        clearTimerData()
    }

    override func tearDown() {
        clearTimerData()
        tracker = nil
        mockDate = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func clearTimerData() {
        UserDefaults.standard.removeObject(forKey: "klaviyo_dwell_timers")
    }

    // MARK: - Save and Remove Tests

    func test_saveTimer_persistsTimerData() {
        // GIVEN
        let geofenceId = "test-geofence-1"
        let startTime = baseTime
        let duration = 60

        // WHEN
        tracker.saveTimer(geofenceId: geofenceId, startTime: startTime, duration: duration, companyId: testCompanyId)

        // THEN - Timer should be persisted
        let expiredTimers = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimers.count, 0, "Timer should not be expired yet")
    }

    func test_removeTimer_removesPersistedData() {
        // GIVEN - Save a timer
        let geofenceId = "test-geofence-1"
        tracker.saveTimer(geofenceId: geofenceId, startTime: baseTime, duration: 60, companyId: testCompanyId)

        // WHEN - Remove the timer
        tracker.removeTimer(geofenceId: geofenceId)

        // THEN - Timer should be gone
        let expiredTimers = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimers.count, 0, "No timers should exist after removal")
    }

    func test_saveTimer_overwritesExistingTimer() {
        // GIVEN - Save a timer with initial duration
        let geofenceId = "test-geofence-1"
        tracker.saveTimer(geofenceId: geofenceId, startTime: baseTime, duration: 60, companyId: testCompanyId)

        // WHEN - Save again with different duration
        tracker.saveTimer(geofenceId: geofenceId, startTime: baseTime, duration: 120, companyId: testCompanyId)

        // THEN - Should have the new duration
        // Advance time by 70 seconds (more than 60, less than 120)
        mockDate = Date(timeIntervalSince1970: baseTime + 70.0)
        let expiredTimers = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimers.count, 0, "Timer with 120s duration should not be expired at 70s")
    }

    // MARK: - Expired Timer Tests

    func test_getExpiredTimers_returnsExpiredTimers() {
        // GIVEN - Save a timer that started 70 seconds ago with 60 second duration
        let geofenceId = "test-geofence-1"
        let startTime = baseTime - 70.0
        tracker.saveTimer(geofenceId: geofenceId, startTime: startTime, duration: 60, companyId: testCompanyId)

        // WHEN - Check for expired timers (current time is baseTime, 70s later)
        mockDate = Date(timeIntervalSince1970: baseTime)
        let expiredTimers = tracker.getExpiredTimers()

        // THEN - Should find expired timer
        XCTAssertEqual(expiredTimers.count, 1, "Should find one expired timer")
        XCTAssertEqual(expiredTimers[0].geofenceId, geofenceId, "Expired timer should match geofence ID")
        XCTAssertEqual(expiredTimers[0].duration, 60, "Expired timer should have correct duration")
        XCTAssertEqual(expiredTimers[0].companyId, testCompanyId, "Expired timer should have correct company ID")
    }

    func test_getExpiredTimers_returnsEmptyWhenNoExpiredTimers() {
        // GIVEN - Save a timer that started 30 seconds ago with 60 second duration
        let geofenceId = "test-geofence-1"
        let startTime = baseTime - 30.0
        tracker.saveTimer(geofenceId: geofenceId, startTime: startTime, duration: 60, companyId: testCompanyId)

        // WHEN - Check for expired timers (current time is baseTime, only 30s later)
        mockDate = Date(timeIntervalSince1970: baseTime)
        let expiredTimers = tracker.getExpiredTimers()

        // THEN - Should not find expired timer
        XCTAssertEqual(expiredTimers.count, 0, "Should not find expired timer when duration not met")
    }

    func test_getExpiredTimers_returnsExpiredTimerAtBoundary() {
        // GIVEN - Save a timer that started exactly 60 seconds ago with 60 second duration
        let geofenceId = "test-geofence-1"
        let startTime = baseTime - 60.0
        tracker.saveTimer(geofenceId: geofenceId, startTime: startTime, duration: 60, companyId: testCompanyId)

        // WHEN - Check for expired timers (current time is baseTime, exactly 60s later)
        mockDate = Date(timeIntervalSince1970: baseTime)
        let expiredTimers = tracker.getExpiredTimers()

        // THEN - Should find expired timer (>= duration)
        XCTAssertEqual(expiredTimers.count, 1, "Should find expired timer at boundary")
    }

    func test_getExpiredTimers_handlesMultipleTimers() {
        // GIVEN - Save multiple timers with different states
        let geofence1 = "geofence-1" // Expired (started 70s ago, 60s duration)
        let geofence2 = "geofence-2" // Not expired (started 30s ago, 60s duration)
        let geofence3 = "geofence-3" // Expired (started 120s ago, 90s duration)

        tracker.saveTimer(geofenceId: geofence1, startTime: baseTime - 70.0, duration: 60, companyId: testCompanyId)
        tracker.saveTimer(geofenceId: geofence2, startTime: baseTime - 30.0, duration: 60, companyId: testCompanyId)
        tracker.saveTimer(geofenceId: geofence3, startTime: baseTime - 120.0, duration: 90, companyId: testCompanyId)

        // WHEN - Check for expired timers
        mockDate = Date(timeIntervalSince1970: baseTime)
        let expiredTimers = tracker.getExpiredTimers()

        // THEN - Should find only expired timers
        XCTAssertEqual(expiredTimers.count, 2, "Should find two expired timers")
        let expiredIds = Set(expiredTimers.map(\.geofenceId))
        XCTAssertTrue(expiredIds.contains(geofence1), "geofence1 should be expired")
        XCTAssertTrue(expiredIds.contains(geofence3), "geofence3 should be expired")
        XCTAssertFalse(expiredIds.contains(geofence2), "geofence2 should not be expired")
    }

    // MARK: - Active Timer Deduplication Tests

    func test_getExpiredTimers_doesNotRemoveActiveTimersFromPersistence() {
        // GIVEN - Save a timer that's not expired yet
        let geofenceId = "test-geofence-1"
        tracker.saveTimer(geofenceId: geofenceId, startTime: baseTime - 30.0, duration: 60, companyId: testCompanyId)

        // WHEN - Check for expired timers (timer is not expired, so won't be returned)
        mockDate = Date(timeIntervalSince1970: baseTime)
        let expiredTimers = tracker.getExpiredTimers()

        // THEN - Should not return timer (it's not expired)
        XCTAssertEqual(expiredTimers.count, 0, "Should not return timer that hasn't expired")

        // Verify timer is still in persistence (not removed because it's not expired)
        let expiredTimersAfter = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimersAfter.count, 0, "Timer should still not be expired")

        // Verify timer data still exists in persistence by checking if it would be expired later
        mockDate = Date(timeIntervalSince1970: baseTime + 40.0) // 70 seconds total (expired)
        let expiredTimersLater = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimersLater.count, 1, "Timer should be expired after enough time passes")
    }

    func test_getExpiredTimers_handlesMixOfActiveAndExpiredTimers() {
        // GIVEN - Save multiple timers (both expired)
        // Note: In practice, if a timer is active in memory, persistence should have been
        // updated when it started. This test verifies that expired timers are returned
        // regardless of activeTimerIds parameter (which is now unused but kept for API compatibility)
        let geofence1 = "geofence-1"
        let geofence2 = "geofence-2"

        tracker.saveTimer(geofenceId: geofence1, startTime: baseTime - 70.0, duration: 60, companyId: testCompanyId)
        tracker.saveTimer(geofenceId: geofence2, startTime: baseTime - 70.0, duration: 60, companyId: testCompanyId)

        // WHEN - Check for expired timers
        mockDate = Date(timeIntervalSince1970: baseTime)
        let expiredTimers = tracker.getExpiredTimers()

        // THEN - Should return all expired timers (activeTimerIds parameter is no longer used)
        XCTAssertEqual(expiredTimers.count, 2, "Should find both expired timers")
        let expiredIds = Set(expiredTimers.map(\.geofenceId))
        XCTAssertTrue(expiredIds.contains(geofence1), "Should return geofence1")
        XCTAssertTrue(expiredIds.contains(geofence2), "Should return geofence2")
    }

    // MARK: - Cleanup Tests

    func test_getExpiredTimers_removesExpiredTimersFromPersistence() {
        // GIVEN - Save an expired timer
        let geofenceId = "test-geofence-1"
        tracker.saveTimer(geofenceId: geofenceId, startTime: baseTime - 70.0, duration: 60, companyId: testCompanyId)

        // WHEN - Check for expired timers
        mockDate = Date(timeIntervalSince1970: baseTime)
        _ = tracker.getExpiredTimers()

        // THEN - Timer should be removed from persistence
        let expiredTimersAfter = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimersAfter.count, 0, "Expired timer should be removed from persistence")
    }

    func test_getExpiredTimers_returnsEmptyWhenNoTimersExist() {
        // GIVEN - No timers saved

        // WHEN - Check for expired timers
        let expiredTimers = tracker.getExpiredTimers()

        // THEN - Should return empty
        XCTAssertEqual(expiredTimers.count, 0, "Should return empty when no timers exist")
    }

    // MARK: - Integration Tests

    func test_fullTimerLifecycle() {
        // GIVEN - Save a timer
        let geofenceId = "test-geofence-1"
        let startTime = baseTime
        tracker.saveTimer(geofenceId: geofenceId, startTime: startTime, duration: 60, companyId: testCompanyId)

        // WHEN - Check immediately (should not be expired)
        mockDate = Date(timeIntervalSince1970: baseTime)
        var expiredTimers = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimers.count, 0, "Timer should not be expired immediately")

        // WHEN - Check after 30 seconds (should still not be expired)
        mockDate = Date(timeIntervalSince1970: baseTime + 30.0)
        expiredTimers = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimers.count, 0, "Timer should not be expired after 30 seconds")

        // WHEN - Check after 60 seconds (should be expired)
        mockDate = Date(timeIntervalSince1970: baseTime + 60.0)
        expiredTimers = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimers.count, 1, "Timer should be expired after 60 seconds")
        XCTAssertEqual(expiredTimers[0].geofenceId, geofenceId, "Expired timer should match")
        XCTAssertEqual(expiredTimers[0].duration, 60, "Expired timer should have correct duration")
        XCTAssertEqual(expiredTimers[0].companyId, testCompanyId, "Expired timer should have correct company ID")

        // WHEN - Check again (should be removed)
        expiredTimers = tracker.getExpiredTimers()
        XCTAssertEqual(expiredTimers.count, 0, "Expired timer should be removed after first check")
    }
}
