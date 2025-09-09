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
public struct Geofence: Equatable, Hashable {
    /// The geofence ID is a combination of the company ID and location ID from Klaviyo, separated by a hyphen.
    public let id: String

    /// Longitude of the geofence center
    public let longitude: Double

    /// Latitude of the geofence center
    public let latitude: Double

    /// Radius of the geofence in meters
    public let radius: Double

    /// Company ID to which this geofence belongs, extracted from the geofence ID.
    public var companyId: String {
        id.split(separator: "-").first.map(String.init) ?? ""
    }

    /// Location ID to which this geofence belongs, extracted from the geofence ID.
    public var locationId: String {
        let components = id.split(separator: "-")
        return components.count > 1 ? String(components[1]) : ""
    }

    /// Creates a new geofence
    /// - Parameters:
    ///   - id: Unique identifier for the geofence
    ///   - longitude: Longitude coordinate of the geofence center
    ///   - latitude: Latitude coordinate of the geofence center
    ///   - radius: Radius of the geofence in meters
    public init(
        id: String,
        longitude: Double,
        latitude: Double,
        radius: Double,
    ) {
        self.id = id
        self.longitude = longitude
        self.latitude = latitude
        self.radius = radius
    }

    /// Converts this geofence to a Core Location circular region
    /// - Returns: A CLCircularRegion instance
    public func toCLCircularRegion() -> CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: id
        )
        return region
    }
}

// MARK: - JSON Decoding Extensions

extension Geofence {
    /// Decodes geofences from JSON data
    /// - Parameter data: JSON data containing geofence information
    /// - Returns: Array of decoded Geofence objects
    /// - Throws: DecodingError if the JSON structure is invalid
    public static func decode(from data: Data) throws -> [Geofence] {
        // First, try to decode as the expected API response format with "data" wrapper
        do {
            let apiDataArray = try JSONDecoder().decode([GeofenceAPIData].self, from: data)
            return apiDataArray.compactMap { apiData in
                Geofence(
                    id: apiData.identifier,
                    longitude: apiData.center.longitude,
                    latitude: apiData.center.latitude,
                    radius: apiData.radius
                )
            }
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to decode geofences: \(error.localizedDescription)"
                )
            )
        }
    }
}

extension CLCircularRegion {
    func toKlaviyoGeofence() -> Geofence {
        Geofence(id: identifier, longitude: center.longitude, latitude: center.latitude, radius: radius)
    }
}

// MARK: - Private API Response Models

/// Center coordinates for a geofence
private struct GeofenceCenter: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

/// Individual geofence data from API response
private struct GeofenceAPIData: Codable, Equatable {
    let identifier: String
    let location: String
    let radius: Double
    let center: GeofenceCenter
}
