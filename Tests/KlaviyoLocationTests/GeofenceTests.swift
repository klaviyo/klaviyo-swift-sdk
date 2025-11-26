//
//  GeofenceTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

@testable import KlaviyoLocation
@testable import KlaviyoSwift
import CoreLocation
import Foundation
import KlaviyoCore
import XCTest

final class GeofenceTests: XCTestCase {
    // MARK: - Initialization Tests

    func testGeofenceInitialization() throws {
        let geofence = try Geofence(
            id: "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )

        XCTAssertEqual(geofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:")
        XCTAssertEqual(geofence.longitude, -122.03026995144546)
        XCTAssertEqual(geofence.latitude, 37.33204742438631)
        XCTAssertEqual(geofence.radius, 100.0)
        XCTAssertEqual(geofence.companyId, "ABC123")
        XCTAssertEqual(geofence.locationId, "8db4effa-44f1-45e6-a88d-8e7d50516a0f")
        XCTAssertNil(geofence.duration)
    }

    func testGeofenceInitializationWithDuration() throws {
        let geofence = try Geofence(
            id: "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:300",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )

        XCTAssertEqual(geofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:300")
        XCTAssertEqual(geofence.longitude, -122.03026995144546)
        XCTAssertEqual(geofence.latitude, 37.33204742438631)
        XCTAssertEqual(geofence.radius, 100.0)
        XCTAssertEqual(geofence.companyId, "ABC123")
        XCTAssertEqual(geofence.locationId, "8db4effa-44f1-45e6-a88d-8e7d50516a0f")
        XCTAssertEqual(geofence.duration, 300)
    }

    func testGeofenceRequiresFourComponents() throws {
        // Test that geofence IDs must have exactly 4 components (3 colons)
        // IDs with only 3 components should result in empty companyId/locationId
        let invalidGeofence = try Geofence(
            id: "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )
        XCTAssertEqual(invalidGeofence.companyId, "", "Company ID should be empty for invalid format")
        XCTAssertEqual(invalidGeofence.locationId, "", "Location ID should be empty for invalid format")
        XCTAssertNil(invalidGeofence.duration, "Duration should be nil for invalid format")

        // Test that valid 4-component IDs work correctly
        let validGeofence = try Geofence(
            id: "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )
        XCTAssertEqual(validGeofence.companyId, "ABC123", "Company ID should be extracted correctly")
        XCTAssertEqual(validGeofence.locationId, "8db4effa-44f1-45e6-a88d-8e7d50516a0f", "Location ID should be extracted correctly")
    }

    // MARK: - Core Location Conversion Tests

    func testToCLCircularRegion() throws {
        let geofence = try Geofence(
            id: "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )

        let clRegion = geofence.toCLCircularRegion()

        XCTAssertEqual(clRegion.identifier, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:")
        XCTAssertEqual(clRegion.center.longitude, -122.03026995144546)
        XCTAssertEqual(clRegion.center.latitude, 37.33204742438631)
        XCTAssertEqual(clRegion.radius, 100.0)
    }

    // MARK: - JSON Decoding Tests

    func testDecodeEmptyArray() throws {
        let jsonData = "[]".data(using: .utf8)!
        let geofences = try JSONDecoder().decode([Geofence].self, from: jsonData)
        XCTAssertEqual(geofences.count, 0)
    }

    func testDecodeInvalidJSON() {
        let invalidJSON = "invalid json".data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode([Geofence].self, from: invalidJSON)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDecodeMissingRequiredFields() {
        let jsonData = """
        [
            {
                "id": "test",
                "radius": 100
            }
        ]
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode([Geofence].self, from: jsonData)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDecodeInvalidDataType() {
        let jsonData = """
        [
            {
                "id": "test",
                "location": "test",
                "radius": "invalid_radius"
                "latitude": 37.33204742438631,
                "longitude": -122.03026995144546
            }
        ]
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode([Geofence].self, from: jsonData)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    // MARK: - GeofenceService Transformation Tests

    func testGeofenceServiceAppendsCompanyIdToUUID() async throws {
        // Given
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: "ABC123")
        let testData = KlaviyoLocationTestUtils.createTestGeofenceData()
        let geofenceService = GeofenceService()

        // When
        let geofences = try await geofenceService.parseGeofences(from: testData, companyId: "ABC123")

        // Then
        XCTAssertEqual(geofences.count, 2)
        let firstGeofence = geofences.first { $0.locationId == "8db4effa-44f1-45e6-a88d-8e7d50516a0f" }!
        XCTAssertEqual(firstGeofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:")
        XCTAssertEqual(firstGeofence.companyId, "ABC123")
        XCTAssertEqual(firstGeofence.latitude, 40.7128)
        XCTAssertEqual(firstGeofence.longitude, -74.006)
        XCTAssertEqual(firstGeofence.radius, 100)
        XCTAssertNil(firstGeofence.duration, "Duration should be nil when not provided in JSON")

        let secondGeofence = geofences.first { $0.locationId == "a84011cf-93ef-4e78-b047-c0ce4ea258e4" }!
        XCTAssertEqual(secondGeofence.id, "_k:ABC123:a84011cf-93ef-4e78-b047-c0ce4ea258e4:")
        XCTAssertEqual(secondGeofence.companyId, "ABC123")
        XCTAssertEqual(secondGeofence.latitude, 40.6892)
        XCTAssertEqual(secondGeofence.longitude, -74.0445)
        XCTAssertEqual(secondGeofence.radius, 200)
        XCTAssertNil(secondGeofence.duration, "Duration should be nil when not provided in JSON")
    }

    func testGeofenceServiceParsesDurationFromJSON() async throws {
        // Given
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: "ABC123")
        let jsonString = """
        {
            "data": [
                {
                    "type": "geofence",
                    "id": "8db4effa-44f1-45e6-a88d-8e7d50516a0f",
                    "attributes": {
                        "latitude": 40.7128,
                        "longitude": -74.006,
                        "radius": 100,
                        "duration": 300
                    }
                },
                {
                    "type": "geofence",
                    "id": "a84011cf-93ef-4e78-b047-c0ce4ea258e4",
                    "attributes": {
                        "latitude": 40.6892,
                        "longitude": -74.0445,
                        "radius": 200,
                        "duration": 60
                    }
                }
            ]
        }
        """
        let testData = jsonString.data(using: .utf8)!
        let geofenceService = GeofenceService()

        // When
        let geofences = try await geofenceService.parseGeofences(from: testData, companyId: "ABC123")

        // Then
        XCTAssertEqual(geofences.count, 2)
        let firstGeofence = geofences.first { $0.locationId == "8db4effa-44f1-45e6-a88d-8e7d50516a0f" }!
        XCTAssertEqual(firstGeofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:300")
        XCTAssertEqual(firstGeofence.duration, 300)

        let secondGeofence = geofences.first { $0.locationId == "a84011cf-93ef-4e78-b047-c0ce4ea258e4" }!
        XCTAssertEqual(secondGeofence.id, "_k:ABC123:a84011cf-93ef-4e78-b047-c0ce4ea258e4:60")
        XCTAssertEqual(secondGeofence.duration, 60)
    }

    func testGeofenceServiceHandlesMixedDurationValues() async throws {
        // Given - one geofence with duration, one without
        KlaviyoLocationTestUtils.setupTestEnvironment(apiKey: "ABC123")
        let jsonString = """
        {
            "data": [
                {
                    "type": "geofence",
                    "id": "8db4effa-44f1-45e6-a88d-8e7d50516a0f",
                    "attributes": {
                        "latitude": 40.7128,
                        "longitude": -74.006,
                        "radius": 100,
                        "duration": 120
                    }
                },
                {
                    "type": "geofence",
                    "id": "a84011cf-93ef-4e78-b047-c0ce4ea258e4",
                    "attributes": {
                        "latitude": 40.6892,
                        "longitude": -74.0445,
                        "radius": 200
                    }
                }
            ]
        }
        """
        let testData = jsonString.data(using: .utf8)!
        let geofenceService = GeofenceService()

        // When
        let geofences = try await geofenceService.parseGeofences(from: testData, companyId: "ABC123")

        // Then
        XCTAssertEqual(geofences.count, 2)
        let firstGeofence = geofences.first { $0.locationId == "8db4effa-44f1-45e6-a88d-8e7d50516a0f" }!
        XCTAssertEqual(firstGeofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f:120")
        XCTAssertEqual(firstGeofence.duration, 120)

        let secondGeofence = geofences.first { $0.locationId == "a84011cf-93ef-4e78-b047-c0ce4ea258e4" }!
        XCTAssertEqual(secondGeofence.id, "_k:ABC123:a84011cf-93ef-4e78-b047-c0ce4ea258e4:")
        XCTAssertNil(secondGeofence.duration)
    }
}
