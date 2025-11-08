//
//  KlaviyoLocationManagerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

@testable import KlaviyoLocation
import CoreLocation
import Foundation
import KlaviyoCore
import XCTest

// MARK: - Test Class

final class KlaviyoLocationManagerTests: XCTestCase {
    var locationManager: KlaviyoLocationManager!
    var mockLocationManager: MockLocationManager!
    var originalEnvironment: KlaviyoEnvironment!
    var mockAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways

    override func setUp() {
        super.setUp()
        mockLocationManager = MockLocationManager()
        locationManager = KlaviyoLocationManager(locationManager: mockLocationManager)
        originalEnvironment = environment
        environment = createMockEnvironment()
    }

    override func tearDown() {
        environment = originalEnvironment
        locationManager = nil
        mockLocationManager = nil
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

    func test_startGeofenceMonitoring_returns_early_when_not_authorized() async {
        // GIVEN
        mockAuthorizationStatus = .denied

        // WHEN
        await locationManager.startGeofenceMonitoring()

        // THEN - No crash, early return
        // Behavior verified through logs and lack of region monitoring
    }

    func test_stopGeofenceMonitoring_stops_monitoring_all_regions() {
        // GIVEN - Add some mock monitored regions
        let region1 = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), radius: 100, identifier: "test1")
        let region2 = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 1, longitude: 1), radius: 100, identifier: "test2")
        mockLocationManager.monitoredRegions = [region1, region2]

        // WHEN
        locationManager.stopGeofenceMonitoring()

        // THEN - All regions should be stopped
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(region1),
                      "stopGeofenceMonitoring should stop monitoring region1")
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(region2),
                      "stopGeofenceMonitoring should stop monitoring region2")
    }
}

// MARK: - Mock Classes

class MockLocationManager: LocationManagerProtocol {
    var delegate: CLLocationManagerDelegate?
    var allowsBackgroundLocationUpdates: Bool = false
    var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var monitoredRegions: Set<CLRegion> = []
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var stoppedRegions: [CLRegion] = []
    var mockIsMonitoringAvailable: Bool = true

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
    func startMonitoring(for region: CLRegion) {
        monitoredRegions.insert(region)
    }

    func stopMonitoring(for region: CLRegion) {
        stoppedRegions.append(region)
        monitoredRegions.remove(region)
    }

    func isMonitoringAvailable(for regionClass: AnyClass) -> Bool {
        mockIsMonitoringAvailable
    }

    func startMonitoringSignificantLocationChanges() {}
    func stopMonitoringSignificantLocationChanges() {}
}
