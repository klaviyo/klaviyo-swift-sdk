//
//  GeofenceCooldownTrackerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

@testable import KlaviyoLocation
import Foundation
import KlaviyoCore
import KlaviyoSwift
import XCTest

final class GeofenceCooldownTrackerTests: XCTestCase {
    var tracker: GeofenceCooldownTracker!
    var testUserDefaults: UserDefaults!
    var mockDate: Date!
    let baseTime: TimeInterval = 1_700_000_000 // Fixed base time for testing

    override func setUp() {
        super.setUp()

        // Use a test suite for UserDefaults to avoid polluting real UserDefaults
        testUserDefaults = UserDefaults(suiteName: "com.klaviyo.test.geofence.cooldown")
        testUserDefaults?.removePersistentDomain(forName: "com.klaviyo.test.geofence.cooldown")

        // Set up mock date that we can control
        mockDate = Date(timeIntervalSince1970: baseTime)

        // Set up test environment with controlled date
        environment = KlaviyoEnvironment.test()
        environment.date = { [weak self] in
            self?.mockDate ?? Date()
        }

        tracker = GeofenceCooldownTracker()

        // Override UserDefaults.standard in the tracker by using a testable approach
        // Since we can't easily inject UserDefaults, we'll use a test suite
        // For now, we'll test with the actual implementation and clean up after each test
        clearCooldownData()
    }

    override func tearDown() {
        clearCooldownData()
        tracker = nil
        testUserDefaults = nil
        mockDate = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func clearCooldownData() {
        UserDefaults.standard.removeObject(forKey: "geofence_cooldowns")
    }

    private func setCooldownData(_ data: [String: TimeInterval]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            UserDefaults.standard.set(jsonData, forKey: "geofence_cooldowns")
        }
    }

    private func getCooldownData() -> [String: TimeInterval]? {
        guard let data = UserDefaults.standard.data(forKey: "geofence_cooldowns"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var result: [String: TimeInterval] = [:]
        for (key, value) in json {
            if let timestamp = value as? TimeInterval {
                result[key] = timestamp
            } else if let timestampDouble = value as? Double {
                result[key] = timestampDouble
            }
        }
        return result
    }

    // MARK: - Basic Cooldown Tests

    func test_firstTransition_isAllowed() {
        // GIVEN - No previous transitions
        let geofenceId = "test-geofence-1"

        // WHEN - Check if first transition is allowed
        let isAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)

        // THEN - Should be allowed
        XCTAssertTrue(isAllowed, "First transition should always be allowed")
    }

    func test_transitionWithinCooldown_isBlocked() {
        // GIVEN - Record a transition 30 seconds ago (within 60s cooldown)
        let geofenceId = "test-geofence-1"
        let transitionTime = baseTime - 30.0

        mockDate = Date(timeIntervalSince1970: transitionTime)
        tracker.recordTransition(geofenceId: geofenceId, transition: .geofenceEnter)

        // WHEN - Try to transition again (current time is baseTime, 30s later)
        mockDate = Date(timeIntervalSince1970: baseTime)
        let isAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)

        // THEN - Should be blocked
        XCTAssertFalse(isAllowed, "Transition within cooldown period should be blocked")
    }

    func test_transitionAfterCooldown_isAllowed() {
        // GIVEN - Record a transition 70 seconds ago (beyond 60s cooldown)
        let geofenceId = "test-geofence-1"
        let transitionTime = baseTime - 70.0

        mockDate = Date(timeIntervalSince1970: transitionTime)
        tracker.recordTransition(geofenceId: geofenceId, transition: .geofenceEnter)

        // WHEN - Try to transition again (current time is baseTime, 70s later)
        mockDate = Date(timeIntervalSince1970: baseTime)
        let isAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)

        // THEN - Should be allowed
        XCTAssertTrue(isAllowed, "Transition after cooldown period should be allowed")
    }

    func test_transitionAtCooldownBoundary_isAllowed() {
        // GIVEN - Record a transition exactly 60 seconds ago (at cooldown boundary)
        let geofenceId = "test-geofence-1"
        let transitionTime = baseTime - 60.0

        mockDate = Date(timeIntervalSince1970: transitionTime)
        tracker.recordTransition(geofenceId: geofenceId, transition: .geofenceEnter)

        // WHEN - Try to transition again (current time is baseTime, exactly 60s later)
        mockDate = Date(timeIntervalSince1970: baseTime)
        let isAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)

        // THEN - Should be allowed (>= cooldown period)
        XCTAssertTrue(isAllowed, "Transition at cooldown boundary should be allowed")
    }

    // MARK: - Independent Cooldown Per Geofence Tests

    func test_trackerEnforcesIndependentCooldownPerGeofence() {
        // GIVEN - Record recent transition for geofence1 (30 seconds ago)
        let geofence1 = "geofence-1"
        let geofence2 = "geofence-2"
        let transitionTime = baseTime - 30.0

        mockDate = Date(timeIntervalSince1970: transitionTime)
        tracker.recordTransition(geofenceId: geofence1, transition: .geofenceEnter)

        // WHEN - Check transitions for both geofences
        mockDate = Date(timeIntervalSince1970: baseTime)
        let geofence1Allowed = tracker.isAllowed(geofenceId: geofence1, transition: .geofenceEnter)
        let geofence2Allowed = tracker.isAllowed(geofenceId: geofence2, transition: .geofenceEnter)

        // THEN - geofence1 should be blocked, geofence2 should be allowed
        XCTAssertFalse(geofence1Allowed, "geofence1 should be blocked (within cooldown)")
        XCTAssertTrue(geofence2Allowed, "geofence2 should be allowed (different geofence)")
    }

    // MARK: - Independent Cooldown Per Transition Type Tests

    func test_trackerEnforcesIndependentCooldownPerTransitionType() {
        // GIVEN - Record recent ENTER transition (30 seconds ago)
        let geofenceId = "test-geofence-1"
        let transitionTime = baseTime - 30.0

        mockDate = Date(timeIntervalSince1970: transitionTime)
        tracker.recordTransition(geofenceId: geofenceId, transition: .geofenceEnter)

        // WHEN - Check both ENTER and EXIT transitions
        mockDate = Date(timeIntervalSince1970: baseTime)
        let enterAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)
        let exitAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceExit)

        // THEN - ENTER should be blocked, EXIT should be allowed
        XCTAssertFalse(enterAllowed, "ENTER should be blocked (within cooldown)")
        XCTAssertTrue(exitAllowed, "EXIT should be allowed (different transition type)")
    }

    func test_trackerHandlesDwellTransition() {
        // GIVEN - Record recent DWELL transition
        let geofenceId = "test-geofence-1"
        let transitionTime = baseTime - 30.0

        mockDate = Date(timeIntervalSince1970: transitionTime)
        tracker.recordTransition(geofenceId: geofenceId, transition: .geofenceDwell)

        // WHEN - Check DWELL and other transitions
        mockDate = Date(timeIntervalSince1970: baseTime)
        let dwellAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceDwell)
        let enterAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)

        // THEN - DWELL should be blocked, ENTER should be allowed
        XCTAssertFalse(dwellAllowed, "DWELL should be blocked (within cooldown)")
        XCTAssertTrue(enterAllowed, "ENTER should be allowed (different transition type)")
    }

    // MARK: - Stale Entry Cleanup Tests

    func test_saveCooldownMapFiltersStaleEntries() {
        // GIVEN - Store map with both recent and stale entries
        let geofence1 = "geofence-1"
        let geofence2 = "geofence-2"
        let geofence3 = "geofence-3"

        let cooldownData: [String: TimeInterval] = [
            "\(geofence1):geofenceEnter": baseTime - 30.0, // Recent (within 60s)
            "\(geofence2):geofenceEnter": baseTime - 70.0, // Stale (beyond 60s)
            "\(geofence3):geofenceExit": baseTime - 10.0 // Recent
        ]

        setCooldownData(cooldownData)

        // WHEN - Record a new transition (this triggers saveCooldownMap which filters stale entries)
        mockDate = Date(timeIntervalSince1970: baseTime)
        tracker.recordTransition(geofenceId: geofence1, transition: .geofenceEnter)

        // THEN - Verify stale entry was removed during save
        let storedData = getCooldownData()
        XCTAssertNotNil(storedData, "Cooldown data should exist")

        // Recent entries should exist
        XCTAssertNotNil(storedData?["\(geofence1):geofenceEnter"], "Recent entry for geofence1 should exist")
        XCTAssertNotNil(storedData?["\(geofence3):geofenceExit"], "Recent entry for geofence3 should exist")

        // Stale entry should be gone (filtered out during save)
        XCTAssertNil(storedData?["\(geofence2):geofenceEnter"], "Stale entry for geofence2 should be removed")
    }

    // MARK: - Integration Tests

    func test_fullCooldownCycle() {
        // GIVEN - Record a transition
        let geofenceId = "test-geofence-1"
        let initialTime = baseTime

        mockDate = Date(timeIntervalSince1970: initialTime)
        tracker.recordTransition(geofenceId: geofenceId, transition: .geofenceEnter)

        // WHEN - Try to transition immediately (should be blocked)
        let immediatelyAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)
        XCTAssertFalse(immediatelyAllowed, "Should be blocked immediately after recording")

        // WHEN - Try to transition after 30 seconds (should still be blocked)
        mockDate = Date(timeIntervalSince1970: baseTime + 30.0)
        let after30sAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)
        XCTAssertFalse(after30sAllowed, "Should be blocked after 30 seconds")

        // WHEN - Try to transition after 60 seconds (should be allowed)
        mockDate = Date(timeIntervalSince1970: baseTime + 60.0)
        let after60sAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)
        XCTAssertTrue(after60sAllowed, "Should be allowed after 60 seconds")

        // WHEN - Record new transition and verify cooldown resets
        tracker.recordTransition(geofenceId: geofenceId, transition: .geofenceEnter)
        let afterNewRecordAllowed = tracker.isAllowed(geofenceId: geofenceId, transition: .geofenceEnter)
        XCTAssertFalse(afterNewRecordAllowed, "Should be blocked after new transition is recorded")
    }
}
