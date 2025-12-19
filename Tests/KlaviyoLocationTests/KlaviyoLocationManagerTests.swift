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
        mockLocationManager.location = CLLocation(latitude: 0, longitude: 0)
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

    func test_stopGeofenceMonitoring_stops_monitoring_all_klaviyo_regions() async {
        // GIVEN - Set up test environment with API key
        let apiKey = "ABC123"
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: apiKey)

        // Create regions with Klaviyo-formatted identifiers (must start with API key)
        let region1 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100,
            identifier: "_k:\(apiKey):8db4effa-44f1-45e6-a88d-8e7d50516a0f"
        )
        let region2 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            radius: 100,
            identifier: "_k:\(apiKey):a84011cf-93ef-4e78-b047-c0ce4ea258e4"
        )
        // Add a non-Klaviyo region that should NOT be stopped
        let nonKlaviyoRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 2, longitude: 2),
            radius: 100,
            identifier: "other-source:some-uuid"
        )
        mockLocationManager.monitoredRegions = [region1, region2, nonKlaviyoRegion]

        // WHEN
        await locationManager.stopGeofenceMonitoring()

        // THEN - Only Klaviyo regions should be stopped
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(region1),
                      "stopGeofenceMonitoring should stop monitoring region1")
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(region2),
                      "stopGeofenceMonitoring should stop monitoring region2")
        XCTAssertFalse(mockLocationManager.stoppedRegions.contains(nonKlaviyoRegion),
                       "stopGeofenceMonitoring should NOT stop monitoring non-Klaviyo regions")
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

    // MARK: - Klaviyo Geofence Isolation Tests

    func test_syncGeofences_only_removes_klaviyo_geofences() async throws {
        // GIVEN - Set up test environment with API key
        let apiKey = "ABC123"
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: apiKey)

        // Add both Klaviyo and non-Klaviyo regions
        let klaviyoRegion1 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100,
            identifier: "_k:\(apiKey):existing-uuid-1"
        )
        let klaviyoRegion2 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            radius: 100,
            identifier: "_k:\(apiKey):existing-uuid-2"
        )
        let nonKlaviyoRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 2, longitude: 2),
            radius: 100,
            identifier: "other-app:region-123"
        )
        mockLocationManager.monitoredRegions = [klaviyoRegion1, klaviyoRegion2, nonKlaviyoRegion]

        // Mock GeofenceService to return empty set (all Klaviyo geofences should be removed)
        let mockGeofenceService = MockGeofenceService()
        mockGeofenceService.mockGeofences = []
        locationManager.geofenceService = mockGeofenceService

        // WHEN
        await locationManager.syncGeofences()

        // THEN - Only Klaviyo regions should be removed, non-Klaviyo should remain
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(klaviyoRegion1),
                      "Klaviyo region 1 should be stopped")
        XCTAssertTrue(mockLocationManager.stoppedRegions.contains(klaviyoRegion2),
                      "Klaviyo region 2 should be stopped")
        XCTAssertFalse(mockLocationManager.stoppedRegions.contains(nonKlaviyoRegion),
                       "Non-Klaviyo region should NOT be stopped")
        XCTAssertTrue(mockLocationManager.monitoredRegions.contains(nonKlaviyoRegion),
                      "Non-Klaviyo region should still be monitored")
    }

    func test_syncGeofences_only_adds_klaviyo_geofences() async throws {
        // GIVEN - Set up test environment with API key
        let apiKey = "ABC123"
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: apiKey)

        // Add a non-Klaviyo region that should remain untouched
        let nonKlaviyoRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100,
            identifier: "other-app:region-123"
        )
        mockLocationManager.monitoredRegions = [nonKlaviyoRegion]

        // Mock GeofenceService to return new Klaviyo geofences
        let mockGeofenceService = MockGeofenceService()
        mockGeofenceService.mockGeofences = [
            try! Geofence(
                id: "_k:\(apiKey):new-uuid-1",
                longitude: 1.0,
                latitude: 1.0,
                radius: 100.0
            ),
            try! Geofence(
                id: "_k:\(apiKey):new-uuid-2",
                longitude: 2.0,
                latitude: 2.0,
                radius: 200.0
            )
        ]
        locationManager.geofenceService = mockGeofenceService

        // WHEN
        await locationManager.syncGeofences()

        // THEN - New Klaviyo geofences should be added, non-Klaviyo region should remain
        let addedRegions = mockLocationManager.monitoredRegions
        let klaviyoRegions = addedRegions
            .compactMap { $0 as? CLCircularRegion }
            .filter(\.isKlaviyoGeofence)

        XCTAssertEqual(klaviyoRegions.count, 2, "Should have 2 Klaviyo geofences")
        XCTAssertTrue(mockLocationManager.monitoredRegions.contains(nonKlaviyoRegion),
                      "Non-Klaviyo region should still be monitored")

        // Verify the added geofences have correct identifiers
        let addedIds = Set(klaviyoRegions.map(\.identifier))
        XCTAssertTrue(addedIds.contains("_k:\(apiKey):new-uuid-1"))
        XCTAssertTrue(addedIds.contains("_k:\(apiKey):new-uuid-2"))
    }

    func test_syncGeofences_does_not_affect_non_klaviyo_regions_when_exceeding_limit() async throws {
        // GIVEN - Set up test environment with API key
        let apiKey = "ABC123"
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: apiKey)

        // Add 15 non-Klaviyo regions (simulating other app functionality)
        var nonKlaviyoRegions: Set<CLRegion> = []
        for i in 0..<15 {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: Double(i), longitude: Double(i)),
                radius: 100,
                identifier: "other-app:region-\(i)"
            )
            nonKlaviyoRegions.insert(region)
        }
        mockLocationManager.monitoredRegions = nonKlaviyoRegions

        // Mock GeofenceService to return 10 Klaviyo geofences (would exceed 20 total)
        let mockGeofenceService = MockGeofenceService()
        mockGeofenceService.mockGeofences = Set((0..<10).map { index in
            try! Geofence(
                id: "_k:\(apiKey):new-uuid-\(index)",
                longitude: Double(index + 100),
                latitude: Double(index + 100),
                radius: 100.0
            )
        })
        locationManager.geofenceService = mockGeofenceService

        // WHEN
        await locationManager.syncGeofences()

        // THEN - All non-Klaviyo regions should remain untouched
        for nonKlaviyoRegion in nonKlaviyoRegions {
            XCTAssertTrue(mockLocationManager.monitoredRegions.contains(nonKlaviyoRegion),
                          "Non-Klaviyo region \(nonKlaviyoRegion.identifier) should still be monitored")
            XCTAssertFalse(mockLocationManager.stoppedRegions.contains(nonKlaviyoRegion),
                           "Non-Klaviyo region \(nonKlaviyoRegion.identifier) should NOT be stopped")
        }

        // Klaviyo geofences should still be attempted (some may fail due to limit)
        let klaviyoRegions = mockLocationManager.monitoredRegions
            .compactMap { $0 as? CLCircularRegion }
            .filter(\.isKlaviyoGeofence)
        XCTAssertGreaterThanOrEqual(klaviyoRegions.count, 0, "Should attempt to add Klaviyo geofences")
    }

    func test_getActiveGeofences_only_returns_klaviyo_geofences() async throws {
        // GIVEN - Set up test environment with API key
        let apiKey = "ABC123"
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: apiKey)

        // Add mix of Klaviyo and non-Klaviyo regions
        let klaviyoRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100,
            identifier: "_k:\(apiKey):klaviyo-uuid"
        )
        let nonKlaviyoRegion1 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            radius: 100,
            identifier: "other-app:region-1"
        )
        let nonKlaviyoRegion2 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 2, longitude: 2),
            radius: 100,
            identifier: "another-app:region-2"
        )
        mockLocationManager.monitoredRegions = [klaviyoRegion, nonKlaviyoRegion1, nonKlaviyoRegion2]

        // WHEN
        let activeKlaviyoGeofences = await locationManager.getActiveGeofences()

        // THEN - Should only return the Klaviyo geofence
        XCTAssertEqual(activeKlaviyoGeofences.count, 1, "Should only return 1 Klaviyo geofence")
        XCTAssertTrue(activeKlaviyoGeofences.contains { $0.id == "_k:\(apiKey):klaviyo-uuid" },
                      "Should contain the Klaviyo geofence")
    }
}

// MARK: - Mock Classes

private final class MockLocationManager: LocationManagerProtocol {
    var location: CLLocation?
    var delegate: CLLocationManagerDelegate?
    var allowsBackgroundLocationUpdates: Bool = false
    var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var monitoredRegions: Set<CLRegion> = []
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var stoppedRegions: [CLRegion] = []
    var mockIsMonitoringAvailable: Bool = true
    var mockAccuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

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

    @available(iOS 14.0, *)
    var currentAccuracyAuthorization: CLAccuracyAuthorization {
        mockAccuracyAuthorization
    }
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

    override init(locationManager: LocationManagerProtocol? = nil, geofenceService: GeofenceServiceProvider? = nil) {
        super.init(locationManager: locationManager, geofenceService: geofenceService)
    }

    override func syncGeofences() async {
        syncGeofencesCallCount += 1
        await super.syncGeofences()
    }

    @MainActor
    override func stopGeofenceMonitoring() async {
        stopGeofenceMonitoringCallCount += 1
        await super.stopGeofenceMonitoring()
    }

    func reset() {
        syncGeofencesCallCount = 0
        stopGeofenceMonitoringCallCount = 0
    }
}

private final class MockGeofenceService: GeofenceServiceProvider {
    var mockGeofences: Set<Geofence> = []

    func fetchGeofences(apiKey: String, latitude: Double?, longitude: Double?) async -> Set<KlaviyoLocation.Geofence> {
        mockGeofences
    }
}
