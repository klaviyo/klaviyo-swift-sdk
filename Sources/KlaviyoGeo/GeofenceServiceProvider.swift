//
//  GeofenceService.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/9/24.
//

import CoreLocation

public protocol GeofenceServiceProvider {
    func fetchGeofences() async -> Set<CLRegion>
}

public struct GeofenceService: GeofenceServiceProvider {
    public init() {}

    public func fetchGeofences() async -> Set<CLRegion> {
        // TODO: fetch from back-end
        // TODO: fetch from local storage

        // FIXME: remove temporary data and replace with live data
        var newRegions = Set<CLCircularRegion>()

        let region1 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 37.33204742438631, longitude: -122.03026995144546),
            radius: 100, // Radius in Meter
            identifier: "One Infinite Loop" // unique identifier
        )
        region1.notifyOnEntry = true
        region1.notifyOnExit = true
        newRegions.insert(region1)

        let region2 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 40.74859487385327, longitude: -73.98563220742138),
            radius: 100,
            identifier: "Empire State Building")
        region2.notifyOnEntry = true
        region2.notifyOnExit = true
        newRegions.insert(region2)

        let region3 = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 42.353245188054096, longitude: -71.05754685168745),
            radius: 100,
            identifier: "Klaviyo HQ")
        region3.notifyOnEntry = true
        region3.notifyOnExit = true
        newRegions.insert(region3)

        return newRegions
    }
}
