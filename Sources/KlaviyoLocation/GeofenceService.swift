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

protocol GeofenceServiceProvider {
    func fetchGeofences(apiKey: String) async -> Set<Geofence>
}

struct GeofenceService: GeofenceServiceProvider {
    func fetchGeofences(apiKey: String) async -> Set<Geofence> {
        do {
            let data = try await fetchGeofenceData(apiKey: apiKey)
            return try parseGeofences(from: data, companyId: apiKey)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Error fetching geofences: \(error)")
            }
            return Set<Geofence>()
        }
    }

    private func fetchGeofenceData(apiKey: String) async throws -> Data {
        // MARK: - Mock JSON Response (Real fetch code commented out below)

        let mockJSONString = """
        {
            "data": [
                {
                    "type": "geofence",
                    "id": "geofence-1",
                    "attributes": {
                        "latitude": 37.7749,
                        "longitude": -122.4194,
                        "radius": 100.0,
                        "duration": 60
                    }
                },
                {
                    "type": "geofence",
                    "id": "geofence-2",
                    "attributes": {
                        "latitude": 40.7128,
                        "longitude": -74.0060,
                        "radius": 150.0,
                        "duration": 120
                    }
                },
                {
                    "type": "geofence",
                    "id": "geofence-3",
                    "attributes": {
                        "latitude": 34.0522,
                        "longitude": -118.2437,
                        "radius": 200.0,
                        "duration": null
                    }
                }
            ]
        }
        """
        return mockJSONString.data(using: .utf8)!

        // MARK: - Real fetch code (commented out for testing)

        /*
         let endpoint = KlaviyoEndpoint.fetchGeofences(apiKey)
         let klaviyoRequest = KlaviyoRequest(endpoint: endpoint)
         let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 1)
         let result = await environment.klaviyoAPI.send(klaviyoRequest, attemptInfo)

         switch result {
         case let .success(data):
             return data
         case let .failure(error):
             if #available(iOS 14.0, *) {
                 Logger.geoservices.error("Failed to fetch geofences; error: \(error, privacy: .public)")
             }
             throw error
         }
         */
    }

    func parseGeofences(from data: Data, companyId: String) throws -> Set<Geofence> {
        let response = try JSONDecoder().decode(GeofenceJSONResponse.self, from: data)
        return try Set(response.data.map { rawGeofence in
            try Geofence(
                id: "_k:\(companyId):\(rawGeofence.id):\(rawGeofence.attributes.duration.map { String($0) } ?? "")",
                longitude: rawGeofence.attributes.longitude,
                latitude: rawGeofence.attributes.latitude,
                radius: rawGeofence.attributes.radius
            )
        })
    }
}

// MARK: - API Response Models

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
        let duration: Int?
    }
}
