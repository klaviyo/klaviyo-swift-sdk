//
//  KlaviyoLocationManagerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

import CoreLocation
import Foundation
import KlaviyoCore
import KlaviyoLocation
import XCTest

// MARK: - Test Class

final class KlaviyoLocationManagerTests: XCTestCase {
    var locationManager: KlaviyoLocationManager!
    var mockLocationManager: MockLocationManager!
    var mockGeofenceManager: MockKlaviyoGeofenceManager!
    var originalEnvironment: KlaviyoEnvironment!
    var mockAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways

    override func setUp() {
        super.setUp()
        mockLocationManager = MockLocationManager()
        mockGeofenceManager = MockKlaviyoGeofenceManager(locationManager: CLLocationManager())
        locationManager = KlaviyoLocationManager(locationManager: mockLocationManager, geofenceManager: mockGeofenceManager)
        originalEnvironment = environment
        environment = createMockEnvironment()
    }

    override func tearDown() {
        environment = originalEnvironment
        locationManager = nil
        mockLocationManager = nil
        mockGeofenceManager = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockEnvironment() -> KlaviyoEnvironment {
        var mockEnvironment = originalEnvironment
        mockEnvironment?.getLocationAuthorizationStatus = { [weak self] in
            self?.mockAuthorizationStatus ?? .authorizedAlways
        }
        return mockEnvironment!
    }

    // MARK: - Authorization Status Change Tests

    func test_setupGeofencing_respects_environment_authorization_status() async {
        // GIVEN
        mockAuthorizationStatus = .denied
        let initialCallCount = mockGeofenceManager.setupGeofencingCallCount

        // WHEN
        await locationManager.setupGeofencing()

        // THEN
        XCTAssertEqual(mockGeofenceManager.setupGeofencingCallCount, initialCallCount,
                       "setupGeofencing should not be called when environment reports .denied status")
    }

    func test_setupGeofencing_calls_setupGeofencing_when_environment_authorization_status_is_authorizedAlways() async {
        // GIVEN
        mockAuthorizationStatus = .authorizedAlways
        let initialCallCount = mockGeofenceManager.setupGeofencingCallCount

        // WHEN
        await locationManager.setupGeofencing()

        // THEN
        XCTAssertEqual(mockGeofenceManager.setupGeofencingCallCount, initialCallCount + 1,
                       "setupGeofencing should be called when environment reports .authorizedAlways status")
    }

    func test_didChangeAuthorization_calls_setupGeofencing_when_statusIsAuthorizedAlways() {
        // GIVEN
        let initialCallCount = mockGeofenceManager.setupGeofencingCallCount

        // WHEN
        mockLocationManager.simulateAuthorizationChange(to: .authorizedAlways)

        // THEN
        XCTAssertEqual(mockGeofenceManager.setupGeofencingCallCount, initialCallCount + 1,
                       "setupGeofencing should be called when authorization changes to .authorizedAlways via delegate")
    }

    func test_didChangeAuthorization_calls_destroyGeofencing_when_statusIsDenied() {
        // GIVEN
        let initialCallCount = mockGeofenceManager.destroyGeofencingCallCount

        // WHEN
        mockLocationManager.simulateAuthorizationChange(to: .denied)

        // THEN
        XCTAssertEqual(mockGeofenceManager.destroyGeofencingCallCount, initialCallCount + 1,
                       "destroyGeofencing should be called when authorization changes to .denied via delegate")
    }

    func test_didChangeAuthorization_calls_destroyGeofencing_when_statusIsAuthorizedWhenInUse() {
        // GIVEN
        let initialCallCount = mockGeofenceManager.destroyGeofencingCallCount

        // WHEN
        mockLocationManager.simulateAuthorizationChange(to: .authorizedWhenInUse)

        // THEN
        XCTAssertEqual(mockGeofenceManager.destroyGeofencingCallCount, initialCallCount + 1,
                       "destroyGeofencing should be called when authorization changes to .authorizedWhenInUse via delegate")
    }
}

// MARK: - Mock Classes

class MockKlaviyoGeofenceManager: KlaviyoGeofenceManager {
    var setupGeofencingCallCount = 0
    var destroyGeofencingCallCount = 0

    override func setupGeofencing() {
        setupGeofencingCallCount += 1
    }

    override func destroyGeofencing() {
        destroyGeofencingCallCount += 1
    }
}

class MockLocationManager: LocationManagerProtocol {
    var delegate: CLLocationManagerDelegate?
    var allowsBackgroundLocationUpdates: Bool = false
    var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var monitoredRegions: Set<CLRegion> = []
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    // Helper method to simulate authorization status changes
    func simulateAuthorizationChange(to status: CLAuthorizationStatus) {
        currentAuthorizationStatus = status
        let mockCLLocationManager = CLLocationManager()
        if #available(iOS 14.0, *) {
            delegate?.locationManagerDidChangeAuthorization?(mockCLLocationManager)
        } else {
            delegate?.locationManager?(mockCLLocationManager, didChangeAuthorization: status)
        }
    }

    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
    func startMonitoring(for region: CLRegion) {}
    func stopMonitoring(for region: CLRegion) {}
    func startMonitoringSignificantLocationChanges() {}
    func stopMonitoringSignificantLocationChanges() {}
}
