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
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import Combine
import XCTest

// MARK: - Test Class

final class KlaviyoLocationManagerTests: XCTestCase {
    fileprivate var locationManager: MockKlaviyoLocationManager!
    fileprivate var mockLocationManager: MockLocationManager!
    var mockAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways

    var mockApiKeyPublisher: PassthroughSubject<String?, Never>!
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()

        mockLocationManager = MockLocationManager()
        mockApiKeyPublisher = PassthroughSubject<String?, Never>()

        // Set up environment with mock authorization status BEFORE creating location manager
        environment = createMockEnvironment()

        // Set up state publisher BEFORE creating location manager
        let initialState = KlaviyoState(queue: [])
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())

        mockApiKeyPublisher
            .compactMap { $0 }
            .sink { apiKey in
                _ = testStore.send(.initialize(apiKey))
            }
            .store(in: &cancellables)

        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }

        // Create location manager AFTER setting up environment and state publisher
        locationManager = MockKlaviyoLocationManager(locationManager: mockLocationManager)
        locationManager.reset()
    }

    override func tearDown() {
        locationManager = nil
        mockLocationManager = nil
        mockApiKeyPublisher = nil
        cancellables.removeAll()
        KlaviyoInternal.resetAPIKeySubject()

        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockEnvironment() -> KlaviyoEnvironment {
        var mockEnvironment = KlaviyoEnvironment.test()
        mockEnvironment.getLocationAuthorizationStatus = { [weak self] in
            self?.mockAuthorizationStatus ?? .authorizedAlways
        }
        return mockEnvironment
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

    func test_stopGeofenceMonitoring_stops_monitoring_all_regions() async {
        // GIVEN - Add some mock monitored regions
        let region1 = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), radius: 100, identifier: "test1")
        let region2 = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 1, longitude: 1), radius: 100, identifier: "test2")
        mockLocationManager.monitoredRegions = [region1, region2]

        // WHEN
        await locationManager.stopGeofenceMonitoring()

        // THEN - All regions should be stopped
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(region1),
                      "stopGeofenceMonitoring should stop monitoring region1")
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(region2),
                      "stopGeofenceMonitoring should stop monitoring region2")
    }

    func test_startGeofenceMonitoring_called_when_receiving_new_api_key() async {
        // GIVEN - Initialize with an initial API key
        mockAuthorizationStatus = .authorizedAlways
        await locationManager.startGeofenceMonitoring()
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertEqual(locationManager.syncGeofencesCallCount, 1,
                       "syncGeofences should be called once when setting up")

        // WHEN - New API key is received (different from initial)
        mockApiKeyPublisher.send("new-key")
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // THEN - syncGeofences should be called again
        XCTAssertEqual(locationManager.syncGeofencesCallCount, 2,
                       "syncGeofences should be called once after foreground")
    }
}

// MARK: - Mock Classes

private final class MockLocationManager: LocationManagerProtocol {
    var delegate: CLLocationManagerDelegate?
    var allowsBackgroundLocationUpdates: Bool = false
    var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var monitoredRegions: Set<CLRegion> = []
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var stoppedRegions: [CLRegion] = []
    var mockIsMonitoringAvailable: Bool = true

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

private final class MockKlaviyoLocationManager: KlaviyoLocationManager {
    var syncGeofencesCallCount: Int = 0
    var stopGeofenceMonitoringCallCount: Int = 0
    var wasSyncGeofencesCalled: Bool {
        syncGeofencesCallCount > 0
    }

    var wasStopGeofenceMonitoringCalled: Bool {
        stopGeofenceMonitoringCallCount > 0
    }

    override init(locationManager: LocationManagerProtocol? = nil) {
        super.init(locationManager: locationManager ?? MockLocationManager())
    }

    override func syncGeofences() async {
        syncGeofencesCallCount += 1
        await super.syncGeofences()
    }

    @MainActor
    override func stopGeofenceMonitoring() {
        stopGeofenceMonitoringCallCount += 1
        super.stopGeofenceMonitoring()
    }

    func reset() {
        syncGeofencesCallCount = 0
        stopGeofenceMonitoringCallCount = 0
    }
}
