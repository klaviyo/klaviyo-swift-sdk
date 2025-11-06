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
public struct Geofence: Equatable, Hashable, Codable {
    /// The geofence ID is a combination of the company ID, location ID, and optional duration time from Klaviyo, separated by colons
    public let id: String

    /// Longitude of the geofence center
    public let longitude: Double

    /// Latitude of the geofence center
    public let latitude: Double

    /// Radius of the geofence in meters
    public let radius: Double

    /// Company ID to which this geofence belongs, extracted from the geofence ID
    public var companyId: String {
        id.split(separator: ":").first.map(String.init) ?? ""
    }

    /// Location UUID to which this geofence belongs, extracted from the geofence ID
    public var locationId: String {
        let components = id.split(separator: ":")
        return components.count >= 2 ? String(components[1]) : ""
    }

    /// Optional duration time in seconds representing the time spent in a geofence to trigger a dwell event, extracted from the geofence ID
    public var duration: Int? {
        let components = id.split(separator: ":")
        return components.count == 3 ? Int(components[2]) : nil
    }

    /// Creates a new geofence
    /// - Parameters:
    ///   - id: Unique identifier for the geofence in format "{companyId}:{UUID}" or "{companyId}:{UUID}:{duration}" where companyId is 6 alphanumeric characters
    ///   - longitude: Longitude coordinate of the geofence center
    ///   - latitude: Latitude coordinate of the geofence center
    ///   - radius: Radius of the geofence in meters
    /// - Throws: `GeofenceError.invalidIdFormat` if the ID doesn't match the expected format
    public init(
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

    /// Validates that the geofence ID follows the expected format: {companyId}:{UUID}:{duration} or {companyId}:{UUID}:
    /// where companyId is exactly 6 alphanumeric characters, UUID follows standard format, and duration is optional
    /// - Parameter id: The ID to validate
    /// - Throws: `GeofenceError.invalidIdFormat` if the format is invalid
    private static func validateIdFormat(_ id: String) throws {
        let pattern = "^[a-zA-Z0-9]{6}:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}:[0-9]*$"
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw GeofenceError.invalidIdFormat("ID must be in format '{companyId}:{geofenceUUID}:{duration}' or '{companyId}:{geofenceUUID}:', got: '\(id)'")
        }
    }

    /// Converts this geofence to a Core Location circular region
    /// The identifier will be in format "{companyId}:{geofenceId}:{duration}" or "{companyId}:{geofenceId}:" if no duration
    /// - Returns: A CLCircularRegion instance
    public func toCLCircularRegion() -> CLCircularRegion {
        let identifier: String
        if let duration {
            identifier = "\(companyId):\(locationId):\(duration)"
        } else {
            identifier = "\(companyId):\(locationId):"
        }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: identifier
        )
        return region
    }
}

/// Errors that can occur when working with geofences
public enum GeofenceError: Error {
    case invalidIdFormat(String)
}

extension CLCircularRegion {
    internal func toKlaviyoGeofence() throws -> Geofence {
        try Geofence(id: identifier, longitude: center.longitude, latitude: center.latitude, radius: radius)
    }

    internal var klaviyoLocationId: String? {
        do {
            return try toKlaviyoGeofence().locationId
        } catch {
            return nil
        }
    }

    internal var klaviyoDuration: Int? {
        do {
            return try toKlaviyoGeofence().duration
        } catch {
            return nil
        }
    }
}
