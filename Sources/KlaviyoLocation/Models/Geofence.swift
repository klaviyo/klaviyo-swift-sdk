//
//  Geofence.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/5/25.
//

import CoreLocation
import Foundation
import KlaviyoCore
import KlaviyoSwift

/// Represents a Klaviyo geofence
struct Geofence: Equatable, Hashable, Codable {
    /// The geofence ID is a combination of the company ID and location ID from Klaviyo, separated by a colon.
    let id: String

    /// Longitude of the geofence center
    let longitude: Double

    /// Latitude of the geofence center
    let latitude: Double

    /// Radius of the geofence in meters
    let radius: Double

    /// Company ID to which this geofence belongs, extracted from the geofence ID.
    var companyId: String {
        id.split(separator: ":").first.map(String.init) ?? ""
    }

    /// Location UUID to which this geofence belongs, extracted from the geofence ID.
    var locationId: String {
        let components = id.split(separator: ":", maxSplits: 1)
        return components.count > 1 ? String(components[1]) : ""
    }

    /// Creates a new geofence
    /// - Parameters:
    ///   - id: Unique identifier for the geofence in format "{companyId}:{UUID}" where companyId is 6 alphanumeric characters
    ///   - longitude: Longitude coordinate of the geofence center
    ///   - latitude: Latitude coordinate of the geofence center
    ///   - radius: Radius of the geofence in meters
    init(
        id: String,
        longitude: Double,
        latitude: Double,
        radius: Double
    ) throws {
        self.id = id
        self.longitude = longitude
        self.latitude = latitude
        self.radius = radius
    }
}

// MARK: - Data Type Conversions

extension Geofence {
    /// Converts this geofence to a Core Location circular region
    /// - Returns: A CLCircularRegion instance
    func toCLCircularRegion() -> CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: id
        )
        return region
    }
}

extension CLCircularRegion {
    /// Checks if this region is a valid Klaviyo geofence
    /// - Returns: `true` if the region identifier matches the Klaviyo geofence format
    func isKlaviyoGeofence(_ apiKey: String) -> Bool {
        identifier.hasPrefix(apiKey)
    }

    func toKlaviyoGeofence() throws -> Geofence {
        try Geofence(id: identifier, longitude: center.longitude, latitude: center.latitude, radius: radius)
    }

    var klaviyoLocationId: String? {
        do {
            return try toKlaviyoGeofence().locationId
        } catch {
            return nil
        }
    }
}
