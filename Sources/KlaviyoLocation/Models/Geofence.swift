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
internal struct Geofence: Equatable, Hashable, Codable {
    /// The geofence ID is a combination of the company ID and location ID from Klaviyo, separated by a colon.
    internal let id: String

    /// Longitude of the geofence center
    internal let longitude: Double

    /// Latitude of the geofence center
    internal let latitude: Double

    /// Radius of the geofence in meters
    internal let radius: Double

    /// Company ID to which this geofence belongs, extracted from the geofence ID.
    internal var companyId: String {
        id.split(separator: ":").first.map(String.init) ?? ""
    }

    /// Location UUID to which this geofence belongs, extracted from the geofence ID.
    internal var locationId: String {
        let components = id.split(separator: ":", maxSplits: 1)
        return components.count > 1 ? String(components[1]) : ""
    }

    /// Creates a new geofence
    /// - Parameters:
    ///   - id: Unique identifier for the geofence in format "{companyId}:{UUID}" where companyId is 6 alphanumeric characters
    ///   - longitude: Longitude coordinate of the geofence center
    ///   - latitude: Latitude coordinate of the geofence center
    ///   - radius: Radius of the geofence in meters
    /// - Throws: `GeofenceError.invalidIdFormat` if the ID doesn't match the expected format
    internal init(
        id: String,
        longitude: Double,
        latitude: Double,
        radius: Double
    ) throws {
        try Self.validateIdFormat(id)
        self.id = id
        self.longitude = longitude
        self.latitude = latitude
        self.radius = radius
    }

    /// Validates that the geofence ID follows the expected format: {companyId}:{UUID}
    /// where companyId is exactly 6 alphanumeric characters and UUID follows standard format
    /// - Parameter id: The ID to validate
    /// - Throws: `GeofenceError.invalidIdFormat` if the format is invalid
    private static func validateIdFormat(_ id: String) throws {
        let pattern = "^[a-zA-Z0-9]{6}:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw GeofenceError.invalidIdFormat("ID must be in format '{companyId}:{geofenceUUID}', got: '\(id)'")
        }
    }
}

/// Errors that can occur when working with geofences
internal enum GeofenceError: Error {
    case invalidIdFormat(String)
}
