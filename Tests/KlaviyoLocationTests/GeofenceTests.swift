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
}
