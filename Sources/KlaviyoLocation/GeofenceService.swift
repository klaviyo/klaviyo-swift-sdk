//
//  GeofenceService.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/9/24.
//

import CoreLocation
import KlaviyoCore

public protocol GeofenceServiceProvider {
    func fetchGeofences() async -> Set<CLRegion>
}

public struct GeofenceService: GeofenceServiceProvider {
    public init() {}

    public func fetchGeofences() async -> Set<CLRegion> {
        // TODO: fetch from back-end
        do {
            // Temporarily override the environment's API URL for this request
            let originalAPIURL = environment.apiURL
            environment.apiURL = {
                var components = URLComponents()
                components.scheme = "https"
                components.host = "mock-api.com"
                return components
            }
            let endpoint = KlaviyoEndpoint.fetchGeofences
            let klaviyoRequest = KlaviyoRequest(endpoint: endpoint)
            let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 50)
            let result = await environment.klaviyoAPI.send(klaviyoRequest, attemptInfo)

            // Restore the original API URL
            environment.apiURL = originalAPIURL

            switch result {
            case .success:
                // TODO: handle geofences - store on device and refresh the ones being monitored for
                print("Successfully fetched geofences from custom URL")
            case .failure:
                // TODO: handle error
                print("Failed to fetch geofences from custom URL")
            }
        } catch {
            // TODO: handle error
            print("Error fetching geofences: \(error)")
        }
        // TODO: fetch from local storage

        // FIXME: remove temporary data and replace with live data
        var newRegions = Set<CLCircularRegion>()

        return newRegions
    }
}
