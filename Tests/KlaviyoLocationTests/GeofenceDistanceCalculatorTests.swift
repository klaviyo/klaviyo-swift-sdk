//
//  GeofenceDistanceCalculatorTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

@testable import KlaviyoLocation
import CoreLocation
import XCTest

final class GeofenceDistanceCalculatorTests: XCTestCase {
    // MARK: - Test Helpers

    private func createGeofence(id: String, latitude: Double, longitude: Double, radius: Double = 100.0) throws -> Geofence {
        try Geofence(
            id: "_k:TEST123:\(id)",
            longitude: longitude,
            latitude: latitude,
            radius: radius
        )
    }

    // MARK: - Basic Filtering Tests

    func testFilterToNearest_ReturnsNearestGeofences() throws {
        // Given: User in Boston, geofences in Boston and NYC
        let userLat = 42.3601 // Boston
        let userLon = -71.0589

        let bostonGeofence = try createGeofence(id: "boston-1", latitude: 42.3601, longitude: -71.0589)
        let nycGeofence = try createGeofence(id: "nyc-1", latitude: 40.7128, longitude: -74.0060)

        let geofences = Set([bostonGeofence, nycGeofence])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 2
        )

        // Then: Boston geofence should be first (closest)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.locationId == "boston-1" })
        XCTAssertTrue(result.contains { $0.locationId == "nyc-1" })
    }

    func testFilterToNearest_RespectsLimit() throws {
        // Given: 5 geofences, limit of 2
        let userLat = 42.3601
        let userLon = -71.0589

        let geofences = try Set([
            createGeofence(id: "loc-1", latitude: 42.3601, longitude: -71.0589), // Closest
            createGeofence(id: "loc-2", latitude: 42.3650, longitude: -71.0520), // Second closest
            createGeofence(id: "loc-3", latitude: 42.3700, longitude: -71.0550), // Third
            createGeofence(id: "loc-4", latitude: 42.3750, longitude: -71.0600), // Fourth
            createGeofence(id: "loc-5", latitude: 40.7128, longitude: -74.0060) // Farthest (NYC)
        ])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 2
        )

        // Then: Should only return 2 geofences
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.locationId == "loc-1" })
        XCTAssertTrue(result.contains { $0.locationId == "loc-2" })
    }

    func testFilterToNearest_ReturnsAllWhenLimitExceedsCount() throws {
        // Given: 3 geofences, limit of 10
        let userLat = 42.3601
        let userLon = -71.0589

        let geofences = try Set([
            createGeofence(id: "loc-1", latitude: 42.3601, longitude: -71.0589),
            createGeofence(id: "loc-2", latitude: 42.3650, longitude: -71.0520),
            createGeofence(id: "loc-3", latitude: 42.3700, longitude: -71.0550)
        ])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 10
        )

        // Then: Should return all 3 geofences
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - Sorting Tests

    func testFilterToNearest_SortsByDistance_ClosestFirst() throws {
        // Given: Geofences at varying distances
        let userLat = 42.3601
        let userLon = -71.0589

        let geofences = try Set([
            createGeofence(id: "far", latitude: 40.7128, longitude: -74.0060), // NYC - farthest
            createGeofence(id: "close", latitude: 42.3601, longitude: -71.0589), // Same location - closest
            createGeofence(id: "medium", latitude: 42.3650, longitude: -71.0520) // Nearby - medium
        ])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 3
        )

        // Then: Should contain all geofences
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains { $0.locationId == "close" })
        XCTAssertTrue(result.contains { $0.locationId == "medium" })
        XCTAssertTrue(result.contains { $0.locationId == "far" })
    }

    func testFilterToNearest_HandlesEqualDistances() throws {
        // Given: Two geofences equidistant from user
        let userLat = 42.3601
        let userLon = -71.0589

        // Two geofences at same distance (symmetrical positions)
        let geofences = try Set([
            createGeofence(id: "north", latitude: 42.3701, longitude: -71.0589), // 0.01° north
            createGeofence(id: "south", latitude: 42.3501, longitude: -71.0589) // 0.01° south
        ])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 2
        )

        // Then: Should return both (order may vary but both should be included)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.locationId == "north" })
        XCTAssertTrue(result.contains { $0.locationId == "south" })
    }

    // MARK: - Edge Cases

    func testFilterToNearest_EmptyCollection() {
        // Given: Empty collection
        let geofences: Set<Geofence> = []

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: 42.3601,
            userLongitude: -71.0589,
            limit: 20
        )

        // Then: Should return empty set
        XCTAssertEqual(result.count, 0)
    }

    func testFilterToNearest_SingleGeofence() throws {
        // Given: Single geofence
        let userLat = 42.3601
        let userLon = -71.0589
        let geofence = try createGeofence(id: "single", latitude: 40.7128, longitude: -74.0060)

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: Set([geofence]),
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 20
        )

        // Then: Should return the single geofence
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.contains { $0.locationId == "single" })
    }

    func testFilterToNearest_DefaultLimit() throws {
        // Given: More than 20 geofences
        let userLat = 42.3601
        let userLon = -71.0589

        var geofences: Set<Geofence> = []
        for i in 0..<25 {
            try geofences.insert(createGeofence(
                id: "loc-\(i)",
                latitude: 42.3601 + Double(i) * 0.001,
                longitude: -71.0589 + Double(i) * 0.001
            ))
        }

        // When: Using default limit (20)
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: userLat,
            userLongitude: userLon
        )

        // Then: Should return exactly 20 geofences
        XCTAssertEqual(result.count, 20)
    }

    // MARK: - Distance Calculation Accuracy Tests

    func testFilterToNearest_DistanceCalculation_CloseProximity() throws {
        // Given: User and geofence very close (should be ~0 meters)
        let userLat = 42.3601
        let userLon = -71.0589

        let geofence = try createGeofence(id: "same", latitude: 42.3601, longitude: -71.0589)

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: Set([geofence]),
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 1
        )

        // Then: Should return the geofence
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.contains { $0.locationId == "same" })
    }

    func testFilterToNearest_DistanceCalculation_BostonToNYC() throws {
        // Given: User in Boston, geofence in NYC
        // Boston: 42.3601, -71.0589
        // NYC: 40.7128, -74.0060
        // Expected distance: ~306 km (~190 miles)
        let userLat = 42.3601
        let userLon = -71.0589

        let bostonGeofence = try createGeofence(id: "boston", latitude: 42.3601, longitude: -71.0589)
        let nycGeofence = try createGeofence(id: "nyc", latitude: 40.7128, longitude: -74.0060)

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: Set([bostonGeofence, nycGeofence]),
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 2
        )

        // Then: Both geofences should be included
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.locationId == "boston" })
        XCTAssertTrue(result.contains { $0.locationId == "nyc" })
    }

    // MARK: - Real-World Scenario Tests

    func testFilterToNearest_BostonAreaGeofences() throws {
        // Given: Multiple geofences around Boston area
        let userLat = 42.3601 // Downtown Boston
        let userLon = -71.0589

        let geofences = try Set([
            createGeofence(id: "downtown", latitude: 42.3601, longitude: -71.0589), // Same location
            createGeofence(id: "north-end", latitude: 42.3650, longitude: -71.0550), // ~0.5km away
            createGeofence(id: "back-bay", latitude: 42.3470, longitude: -71.0820), // ~2km away
            createGeofence(id: "cambridge", latitude: 42.3736, longitude: -71.1189), // ~5km away
            createGeofence(id: "nyc", latitude: 40.7128, longitude: -74.0060) // ~306km away
        ])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: userLat,
            userLongitude: userLon,
            limit: 5
        )

        // Then: Should contain all geofences
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.contains { $0.locationId == "downtown" })
        XCTAssertTrue(result.contains { $0.locationId == "north-end" })
        XCTAssertTrue(result.contains { $0.locationId == "back-bay" })
        XCTAssertTrue(result.contains { $0.locationId == "cambridge" })
        XCTAssertTrue(result.contains { $0.locationId == "nyc" })
    }

    func testFilterToNearest_DifferentUserLocations() throws {
        // Given: Same geofences, different user locations
        let geofences = try Set([
            createGeofence(id: "boston", latitude: 42.3601, longitude: -71.0589),
            createGeofence(id: "nyc", latitude: 40.7128, longitude: -74.0060)
        ])

        // When: User in Boston
        let resultFromBoston = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: 42.3601,
            userLongitude: -71.0589,
            limit: 2
        )

        // When: User in NYC
        let resultFromNYC = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: 40.7128,
            userLongitude: -74.0060,
            limit: 2
        )

        // Then: Both results should contain both geofences
        XCTAssertEqual(resultFromBoston.count, 2)
        XCTAssertTrue(resultFromBoston.contains { $0.locationId == "boston" })
        XCTAssertTrue(resultFromBoston.contains { $0.locationId == "nyc" })

        XCTAssertEqual(resultFromNYC.count, 2)
        XCTAssertTrue(resultFromNYC.contains { $0.locationId == "nyc" })
        XCTAssertTrue(resultFromNYC.contains { $0.locationId == "boston" })
    }

    // MARK: - Limit Edge Cases

    func testFilterToNearest_ZeroLimit() throws {
        // Given: Geofences with limit of 0
        let geofences = try Set([
            createGeofence(id: "loc-1", latitude: 42.3601, longitude: -71.0589)
        ])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: 42.3601,
            userLongitude: -71.0589,
            limit: 0
        )

        // Then: Should return empty set
        XCTAssertEqual(result.count, 0)
    }

    func testFilterToNearest_LimitOne() throws {
        // Given: Multiple geofences, limit of 1
        let geofences = try Set([
            createGeofence(id: "close", latitude: 42.3601, longitude: -71.0589),
            createGeofence(id: "far", latitude: 40.7128, longitude: -74.0060)
        ])

        // When
        let result = GeofenceDistanceCalculator.filterToNearest(
            geofences: geofences,
            userLatitude: 42.3601,
            userLongitude: -71.0589,
            limit: 1
        )

        // Then: Should return only the closest one
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.contains { $0.locationId == "close" })
    }
}
