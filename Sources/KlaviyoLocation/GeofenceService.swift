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
        // TODO: uncomment this block when we can use the real endpoint
//        let endpoint = KlaviyoEndpoint.fetchGeofences
//        let klaviyoRequest = KlaviyoRequest(endpoint: endpoint)
//        let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 1)
//        let result = await environment.klaviyoAPI.send(klaviyoRequest, attemptInfo)
//
//        switch result {
//        case let .success(data):
//            if #available(iOS 14.0, *) {
//                Logger.geoservices.info("Successfully fetched geofences")
//            }
//            return data
//        case let .failure(error):
//            if #available(iOS 14.0, *) {
//                Logger.geoservices.error("Failed to fetch geofences")
//            }
//            throw error
//        }

        // TODO: mocks request with proxyman map local, remove this block when we can use the real endpoint
        guard let url = URL(string: "https://mock-api.com/geofences") else {
            throw NSError(domain: "GeofenceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeofenceService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "GeofenceService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"])
        }

        return data
    }

    /// Parses raw geofence data and transforms it into Geofence objects with the companyId prepended to the id
    internal func parseGeofences(from data: Data) async throws -> Set<Geofence> {
        do {
            let response = try JSONDecoder().decode(GeofenceJSONResponse.self, from: data)
            let companyId = try await KlaviyoInternal.fetchAPIKey()
            let geofences = try response.data.map { rawGeofence in
                try Geofence(
                    id: "\(companyId):\(rawGeofence.id)",
                    longitude: rawGeofence.attributes.longitude,
                    latitude: rawGeofence.attributes.latitude,
                    radius: rawGeofence.attributes.radius,
                    dwell: rawGeofence.attributes.dwell
                )
            }

            return Set(geofences)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Failed to decode geofences from response: \(error)")
            }
            throw error
        }
    }
}

private struct GeofenceJSONResponse: Codable {
    let data: [GeofenceJSON]
}

private struct GeofenceJSON: Codable {
    let type: String
    let id: String
    let attributes: Attributes

    struct Attributes: Codable {
        let latitude: Double
        let longitude: Double
        let radius: Double
        let dwell: Int?
    }
}
