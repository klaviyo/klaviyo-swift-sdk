//
//  GeofenceTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

import CoreLocation
import Foundation
import KlaviyoLocation
import XCTest

final class GeofenceTests: XCTestCase {
    // MARK: - Initialization Tests

    func testGeofenceInitialization() {
        let geofence = Geofence(
            id: "test-geofence",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )

        XCTAssertEqual(geofence.id, "test-geofence")
        XCTAssertEqual(geofence.longitude, -122.03026995144546)
        XCTAssertEqual(geofence.latitude, 37.33204742438631)
        XCTAssertEqual(geofence.radius, 100.0)
        XCTAssertEqual(geofence.companyId, "test")
        XCTAssertEqual(geofence.locationId, "geofence")
    }

    // MARK: - Core Location Conversion Tests

    func testToCLCircularRegion() {
        let geofence = Geofence(
            id: "test-geofence",
            longitude: -122.03026995144546,
            latitude: 37.33204742438631,
            radius: 100.0
        )

        let clRegion = geofence.toCLCircularRegion()

        XCTAssertEqual(clRegion.identifier, "test-geofence")
        XCTAssertEqual(clRegion.center.longitude, -122.03026995144546)
        XCTAssertEqual(clRegion.center.latitude, 37.33204742438631)
        XCTAssertEqual(clRegion.radius, 100.0)
    }

    // MARK: - JSON Decoding Tests

    func testDecodeValidGeofences() throws {
        let jsonData = """
        [
            {
                "identifier": "ABC123-locA",
                "location": "One Infinite Loop",
                "radius": 100,
                "center": {
                    "latitude": 37.33204742438631,
                    "longitude": -122.03026995144546
                }
            },
            {
                "identifier": "ABC123-locB",
                "location": "Empire State Building",
                "radius": 100,
                "center": {
                    "latitude": 40.74859487385327,
                    "longitude": -73.98563220742138
                }
            }
        ]
        """.data(using: .utf8)!

        let geofences = try Geofence.decode(from: jsonData)

        XCTAssertEqual(geofences.count, 2)

        let firstGeofence = geofences[0]
        XCTAssertEqual(firstGeofence.id, "ABC123-locA")
        XCTAssertEqual(firstGeofence.latitude, 37.33204742438631)
        XCTAssertEqual(firstGeofence.longitude, -122.03026995144546)
        XCTAssertEqual(firstGeofence.radius, 100)
        XCTAssertEqual(firstGeofence.companyId, "ABC123")
        XCTAssertEqual(firstGeofence.locationId, "locA")

        let secondGeofence = geofences[1]
        XCTAssertEqual(secondGeofence.id, "ABC123-locB")
        XCTAssertEqual(secondGeofence.latitude, 40.74859487385327)
        XCTAssertEqual(secondGeofence.longitude, -73.98563220742138)
        XCTAssertEqual(secondGeofence.radius, 100)
        XCTAssertEqual(secondGeofence.companyId, "ABC123")
        XCTAssertEqual(secondGeofence.locationId, "locB")
    }

    func testDecodeEmptyArray() throws {
        let jsonData = "[]".data(using: .utf8)!
        let geofences = try Geofence.decode(from: jsonData)
        XCTAssertEqual(geofences.count, 0)
    }

    func testDecodeInvalidJSON() {
        let invalidJSON = "invalid json".data(using: .utf8)!

        XCTAssertThrowsError(try Geofence.decode(from: invalidJSON)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDecodeMissingRequiredFields() {
        let jsonData = """
        [
            {
                "identifier": "test",
                "radius": 100
            }
        ]
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Geofence.decode(from: jsonData)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDecodeInvalidDataType() {
        let jsonData = """
        [
            {
                "identifier": "test",
                "location": "test",
                "radius": "invalid_radius",
                "center": {
                    "latitude": 37.33204742438631,
                    "longitude": -122.03026995144546
                }
            }
        ]
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Geofence.decode(from: jsonData)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
}
