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
            id: "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )

        XCTAssertEqual(geofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f")
        XCTAssertEqual(geofence.longitude, -122.03026995144546)
        XCTAssertEqual(geofence.latitude, 37.33204742438631)
        XCTAssertEqual(geofence.radius, 100.0)
        XCTAssertEqual(geofence.companyId, "ABC123")
        XCTAssertEqual(geofence.locationId, "8db4effa-44f1-45e6-a88d-8e7d50516a0f")
    }

    // MARK: - Core Location Conversion Tests

    func testToCLCircularRegion() throws {
        let geofence = try Geofence(
            id: "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )

        let clRegion = geofence.toCLCircularRegion()

        XCTAssertEqual(clRegion.identifier, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f")
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
        XCTAssertEqual(firstGeofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f")
        XCTAssertEqual(firstGeofence.companyId, "ABC123")
        XCTAssertEqual(firstGeofence.latitude, 40.7128)
        XCTAssertEqual(firstGeofence.longitude, -74.006)
        XCTAssertEqual(firstGeofence.radius, 100)

        let secondGeofence = geofences.first { $0.locationId == "a84011cf-93ef-4e78-b047-c0ce4ea258e4" }!
        XCTAssertEqual(secondGeofence.id, "_k:ABC123:a84011cf-93ef-4e78-b047-c0ce4ea258e4")
        XCTAssertEqual(secondGeofence.companyId, "ABC123")
        XCTAssertEqual(secondGeofence.latitude, 40.6892)
        XCTAssertEqual(secondGeofence.longitude, -74.0445)
        XCTAssertEqual(secondGeofence.radius, 200)
    }

    func testGeofenceServiceHandlesAdditionalFields() async throws {
        // Given - JSON response with additional fields at multiple levels to simulate future API changes
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
                        "name": "New York Store",
                        "description": "Flagship location",
                        "metadata": {
                            "category": "retail",
                            "priority": "high"
                        },
                        "created_at": "2025-01-01T00:00:00Z",
                        "updated_at": "2025-01-02T00:00:00Z",
                        "duration": 10000
                    },
                    "relationships": {
                        "campaigns": {
                            "data": []
                        }
                    },
                    "meta": {
                        "version": "2.0"
                    }
                },
                {
                    "type": "geofence",
                    "id": "a84011cf-93ef-4e78-b047-c0ce4ea258e4",
                    "attributes": {
                        "latitude": 40.6892,
                        "longitude": -74.0445,
                        "radius": 200,
                        "tags": ["downtown", "popular"]
                    }
                }
            ],
        }
        """
        let testData = jsonString.data(using: .utf8)!
        let geofenceService = GeofenceService()

        // When - Parse the response with additional fields
        let geofences = try geofenceService.parseGeofences(from: testData, companyId: "ABC123")

        // Then - Verify parsing succeeds and ignores additional fields
        XCTAssertEqual(geofences.count, 2, "Should parse all geofences despite additional fields")

        let firstGeofence = geofences.first { $0.locationId == "8db4effa-44f1-45e6-a88d-8e7d50516a0f" }!
        XCTAssertEqual(firstGeofence.id, "_k:ABC123:8db4effa-44f1-45e6-a88d-8e7d50516a0f")
        XCTAssertEqual(firstGeofence.companyId, "ABC123")
        XCTAssertEqual(firstGeofence.latitude, 40.7128, "Should correctly parse latitude")
        XCTAssertEqual(firstGeofence.longitude, -74.006, "Should correctly parse longitude")
        XCTAssertEqual(firstGeofence.radius, 100, "Should correctly parse radius")

        let secondGeofence = geofences.first { $0.locationId == "a84011cf-93ef-4e78-b047-c0ce4ea258e4" }!
        XCTAssertEqual(secondGeofence.id, "_k:ABC123:a84011cf-93ef-4e78-b047-c0ce4ea258e4")
        XCTAssertEqual(secondGeofence.companyId, "ABC123")
        XCTAssertEqual(secondGeofence.latitude, 40.6892, "Should correctly parse latitude")
        XCTAssertEqual(secondGeofence.longitude, -74.0445, "Should correctly parse longitude")
        XCTAssertEqual(secondGeofence.radius, 200, "Should correctly parse radius")
    }
}
