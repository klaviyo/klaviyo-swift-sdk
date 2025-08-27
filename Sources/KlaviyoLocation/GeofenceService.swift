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

        return newRegions
    }
}
