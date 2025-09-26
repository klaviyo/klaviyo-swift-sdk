//
//  GeofenceService.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/9/24.
//

import CoreLocation
import KlaviyoCore
import KlaviyoSwift
import OSLog

/// Errors that can occur in GeofenceService
internal enum GeofenceServiceError: Error {
    case apiRequestFailed
    case decodingFailed
}

internal protocol GeofenceServiceProvider {
    func fetchGeofences() async -> Set<Geofence>
}

internal struct GeofenceService: GeofenceServiceProvider {
    internal func fetchGeofences() async -> Set<Geofence> {
        do {
            let data = try await fetchGeofenceData()
            return try await parseGeofences(from: data)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Error fetching geofences: \(error)")
            }
            return Set<Geofence>()
        }
    }

    /// Fetches raw geofence data from the API
    private func fetchGeofenceData() async throws -> Data {
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
            return data
        case .failure:
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Failed to fetch geofences from mock endpoint https://mock-api.com/geofences")
            }
            throw GeofenceServiceError.apiRequestFailed
        }
    }

    /// Parses raw geofence data and transforms it into Geofence objects with the companyId prepended to the id
    internal func parseGeofences(from data: Data) async throws -> Set<Geofence> {
        do {
            let response = try JSONDecoder().decode(GeofenceJSONResponse.self, from: data)
            let companyId = try await KlaviyoInternal.fetchAPIKey()
            let geofences = try response.data.map { rawGeofence in
                try Geofence(
                    id: "\(companyId)-\(rawGeofence.id)",
                    longitude: rawGeofence.attributes.longitude,
                    latitude: rawGeofence.attributes.latitude,
                    radius: rawGeofence.attributes.radius
                )
            }

            return Set(geofences)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Failed to decode geofences from response: \(error)")
            }
            throw GeofenceServiceError.decodingFailed
        }
    }
}

internal struct GeofenceJSONResponse: Codable {
    let data: [GeofenceJSON]
}

internal struct GeofenceJSON: Codable {
    let type: String
    let id: String
    let attributes: Attributes

    struct Attributes: Codable {
        let latitude: Double
        let longitude: Double
        let radius: Double
    }
}
