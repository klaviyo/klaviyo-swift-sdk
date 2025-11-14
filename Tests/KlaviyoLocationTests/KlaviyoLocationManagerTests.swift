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

    var mockLifecycleEvents: PassthroughSubject<LifeCycleEvents, Never>!
    var mockApiKeyPublisher: PassthroughSubject<String?, Never>!
    var cancellables: Set<AnyCancellable> = []
    var lifecycleSubscription: AnyCancellable?

    override func setUp() {
        super.setUp()

        mockLocationManager = MockLocationManager()
        mockLifecycleEvents = PassthroughSubject<LifeCycleEvents, Never>()
        mockApiKeyPublisher = PassthroughSubject<String?, Never>()

        // Set up environment with mock authorization status BEFORE creating location manager
        environment = createMockEnvironment()
        environment.appLifeCycle = AppLifeCycleEvents(lifeCycleEvents: {
            self.mockLifecycleEvents.eraseToAnyPublisher()
        })

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
        lifecycleSubscription?.cancel()
        lifecycleSubscription = nil
        locationManager = nil
        mockLocationManager = nil
        mockLifecycleEvents = nil
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

    func test_startGeofenceMonitoring_called_when_app_foregrounded() async {
        // GIVEN
        mockAuthorizationStatus = .authorizedAlways
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertFalse(locationManager.wasStartGeofenceMonitoringCalled,
                       "startGeofenceMonitoring should not be called initially")

        // WHEN - App is foregrounded
        mockLifecycleEvents.send(.foregrounded)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // THEN - startGeofenceMonitoring should be called
        XCTAssertTrue(locationManager.wasStartGeofenceMonitoringCalled,
                      "startGeofenceMonitoring should be called when app is foregrounded")
        XCTAssertEqual(locationManager.startGeofenceMonitoringCallCount, 1,
                       "startGeofenceMonitoring should be called exactly once")
    }

    func test_startGeofenceMonitoring_called_when_new_api_key() async {
        // GIVEN
        mockAuthorizationStatus = .authorizedAlways
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertFalse(locationManager.wasStartGeofenceMonitoringCalled,
                       "startGeofenceMonitoring should not be called initially")

        // WHEN - New API key is received
        mockApiKeyPublisher.send("new-key")
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // THEN - startGeofenceMonitoring should be called
        XCTAssertTrue(locationManager.wasStartGeofenceMonitoringCalled,
                      "startGeofenceMonitoring should be called when new API key is received")
        XCTAssertEqual(locationManager.startGeofenceMonitoringCallCount, 1,
                       "startGeofenceMonitoring should be called exactly once")
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
    var startGeofenceMonitoringCallCount: Int = 0
    var stopGeofenceMonitoringCallCount: Int = 0
    var wasStartGeofenceMonitoringCalled: Bool {
        startGeofenceMonitoringCallCount > 0
    }

    var wasStopGeofenceMonitoringCalled: Bool {
        stopGeofenceMonitoringCallCount > 0
    }

    override init(locationManager: LocationManagerProtocol? = nil) {
        super.init(locationManager: locationManager ?? MockLocationManager())
    }

    @MainActor
    override func startGeofenceMonitoring() {
        startGeofenceMonitoringCallCount += 1
        super.startGeofenceMonitoring()
    }

    @MainActor
    override func stopGeofenceMonitoring() {
        stopGeofenceMonitoringCallCount += 1
        super.stopGeofenceMonitoring()
    }

    func reset() {
        startGeofenceMonitoringCallCount = 0
        stopGeofenceMonitoringCallCount = 0
    }
}
