//
//  GeofenceDistanceCalculator.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 1/27/25.
//

import CoreLocation
import Foundation

/// Calculates the distance between geographical coordinates using the Haversine formula.
///
/// This calculator provides accurate distance calculations for geofencing operations.
enum GeofenceDistanceCalculator {
    /// Earth's mean radius in meters
    private static let earthRadiusMeters: Double = 6_371_000.0

    /// Calculates the distance between two coordinates in meters using the Haversine formula.
    ///
    /// The Haversine formula calculates the great-circle distance between two points
    /// on a sphere given their longitudes and latitudes, accounting for the Earth's curvature.
    ///
    /// - Parameters:
    ///   - coordinate1: The first coordinate (latitude, longitude)
    ///   - coordinate2: The second coordinate (latitude, longitude)
    /// - Returns: The distance between the two coordinates in meters
    private static func distance(
        from coordinate1: CLLocationCoordinate2D,
        to coordinate2: CLLocationCoordinate2D
    ) -> Double {
        let lat1Rad = coordinate1.latitude * .pi / 180.0
        let lat2Rad = coordinate2.latitude * .pi / 180.0
        let deltaLatRad = (coordinate2.latitude - coordinate1.latitude) * .pi / 180.0
        let deltaLonRad = (coordinate2.longitude - coordinate1.longitude) * .pi / 180.0

        let haversineValue = sin(deltaLatRad / 2.0) * sin(deltaLatRad / 2.0) +
            cos(lat1Rad) * cos(lat2Rad) *
            sin(deltaLonRad / 2.0) * sin(deltaLonRad / 2.0)

        let angularDistanceRadians = 2.0 * atan2(sqrt(haversineValue), sqrt(1.0 - haversineValue))
        let distance = earthRadiusMeters * angularDistanceRadians

        return distance
    }

    /// Calculates the distance from a coordinate to a geofence center in meters.
    ///
    /// - Parameters:
    ///   - coordinate: The coordinate to measure from
    ///   - geofence: The geofence containing the center point
    /// - Returns: The distance from the coordinate to the geofence center in meters
    private static func distance(
        from coordinate: CLLocationCoordinate2D,
        to geofence: Geofence
    ) -> Double {
        let geofenceCoordinate = CLLocationCoordinate2D(
            latitude: geofence.latitude,
            longitude: geofence.longitude
        )
        return distance(from: coordinate, to: geofenceCoordinate)
    }

    /// Filter a set of geofences to the nearest N fences based on distance from a given location.
    ///
    /// Calculates distance from the user location to each geofence center using the Haversine formula,
    /// sorts by distance, and returns the nearest ones up to the specified limit.
    ///
    /// - Parameters:
    ///   - geofences: Set of geofences to filter
    ///   - userLatitude: User's current latitude
    ///   - userLongitude: User's current longitude
    ///   - limit: Maximum number of geofences to return (default 20)
    /// - Returns: Set of nearest geofences
    static func filterToNearest(
        geofences: Set<Geofence>,
        userLatitude: Double,
        userLongitude: Double,
        limit: Int = 20
    ) -> Set<Geofence> {
        let userCoordinate = CLLocationCoordinate2D(
            latitude: userLatitude,
            longitude: userLongitude
        )

        // Calculate distance for each geofence and create tuples
        let geofencesWithDistance = geofences.map { geofence -> (geofence: Geofence, distance: Double) in
            let distance = self.distance(from: userCoordinate, to: geofence)
            return (geofence: geofence, distance: distance)
        }

        // Sort by distance (closest first) and take the first N
        return Set(geofencesWithDistance
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map(\.geofence))
    }
}
