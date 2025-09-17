//
//  GeofenceService.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/9/24.
//

import CoreLocation
import KlaviyoCore
import OSLog

public protocol GeofenceServiceProvider {
    func fetchGeofences() async -> Set<Geofence>
}

public struct GeofenceService: GeofenceServiceProvider {
    public init() {}

    public func fetchGeofences() async -> Set<Geofence> {
        var newRegions = Set<Geofence>()
        do {
            // FIXME: Temporarily override the environment's API URL for this mock request
            let originalAPIURL = environment.apiURL
            environment.apiURL = {
                var components = URLComponents()
                components.scheme = "https"
                components.host = "mock-api.com"
                return components
            }
            let endpoint = KlaviyoEndpoint.fetchGeofences
            let klaviyoRequest = KlaviyoRequest(endpoint: endpoint)
            let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 1)
            let result = await environment.klaviyoAPI.send(klaviyoRequest, attemptInfo)

            // FIXME: Restore the original API URL
            environment.apiURL = originalAPIURL

            switch result {
            case let .success(data):
                do {
                    let geofences = try Geofence.decode(from: data)
                    newRegions = Set(geofences)
                } catch {
                    if #available(iOS 14.0, *) {
                        Logger.geoservices.error("Failed to decode geofences from response: \(error)")
                    }
                }
            case .failure:
                if #available(iOS 14.0, *) {
                    Logger.geoservices.error("Failed to fetch geofences from mock endpoint https://mock-api.com/geofences")
                }
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Error fetching geofences: \(error)")
            }
        }

        return newRegions
    }
}
