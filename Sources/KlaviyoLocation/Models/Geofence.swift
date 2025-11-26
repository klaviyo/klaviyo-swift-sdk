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
    /// The geofence ID in the format "_k:{companyId}:{UUID}:{duration}" with a "_k" prefix, company ID, location ID, and optional duration from Klaviyo, separated by colons.
    let id: String

    /// Longitude of the geofence center
    let longitude: Double

    /// Latitude of the geofence center
    let latitude: Double

    /// Radius of the geofence in meters
    let radius: Double

    /// Company ID to which this geofence belongs, extracted from the geofence ID.
    var companyId: String {
        let components = id.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4, components[0] == "_k" else { return "" }
        return String(components[1])
    }

    /// Location UUID to which this geofence belongs, extracted from the geofence ID.
    var locationId: String {
        let components = id.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4, components[0] == "_k" else { return "" }
        return String(components[2])
    }

    /// Optional duration for this geofence to record a dwell event
    var duration: Int? {
        let components = id.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4, components[0] == "_k" else { return nil }
        let durationString = String(components[3])
        // Return nil if duration component is empty
        guard !durationString.isEmpty else { return nil }
        return Int(durationString)
    }

    /// Creates a new geofence
    /// - Parameters:
    ///   - id: Unique identifier for the geofence in format "_k:{companyId}:{UUID}:{duration}" where duration is optional
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
    /// Checks if this region is a Klaviyo geofence (identified by "_k" prefix)
    /// - Returns: `true` if the region identifier starts with "_k"
    var isKlaviyoGeofence: Bool {
        identifier.hasPrefix("_k:")
    }

    func toKlaviyoGeofence() throws -> Geofence {
        try Geofence(id: identifier, longitude: center.longitude, latitude: center.latitude, radius: radius)
    }
}
