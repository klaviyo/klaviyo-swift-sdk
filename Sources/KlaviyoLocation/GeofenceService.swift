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
    func fetchGeofences(apiKey: String, latitude: Double?, longitude: Double?) async -> Set<Geofence>
}

struct GeofenceService: GeofenceServiceProvider {
    func fetchGeofences(apiKey: String, latitude: Double?, longitude: Double?) async -> Set<Geofence> {
        do {
            let data = try await fetchGeofenceData(apiKey: apiKey, latitude: latitude, longitude: longitude)
            return try parseGeofences(from: data, companyId: apiKey)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Error fetching geofences: \(error)")
            }
            return Set<Geofence>()
        }
    }

    private func fetchGeofenceData(apiKey: String, latitude: Double?, longitude: Double?) async throws -> Data {
        let endpoint = KlaviyoEndpoint.fetchGeofences(apiKey, latitude: latitude, longitude: longitude)
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
    }

    func parseGeofences(from data: Data, companyId: String) throws -> Set<Geofence> {
        let decoder = JSONDecoder()
        let response: GeofenceJSONResponse
        do {
            response = try decoder.decode(GeofenceJSONResponse.self, from: data)
        } catch {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Failed to decode geofence response structure: \(error.localizedDescription, privacy: .public)")
            }
            return Set<Geofence>()
        }

        var geofences: Set<Geofence> = []
        var failedCount = 0

        for rawGeofence in response.data {
            do {
                let geofence = try Geofence(
                    id: "_k:\(companyId):\(rawGeofence.id)",
                    longitude: rawGeofence.attributes.longitude,
                    latitude: rawGeofence.attributes.latitude,
                    radius: rawGeofence.attributes.radius
                )
                geofences.insert(geofence)
            } catch {
                failedCount += 1
                if #available(iOS 14.0, *) {
                    Logger.geoservices.warning("⚠️ Failed to parse geofence \(rawGeofence.id): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if failedCount > 0, #available(iOS 14.0, *) {
            Logger.geoservices.warning("⚠️ Failed to parse \(failedCount) of \(response.data.count) geofences. Continuing with \(geofences.count) successfully parsed geofences.")
        }

        return geofences
    }
}

// MARK: - API Response Models

private struct GeofenceJSONResponse: Codable {
    let data: [GeofenceJSON]

    enum CodingKeys: String, CodingKey {
        case data
    }
}

private struct GeofenceJSON: Codable {
    let type: String
    let id: String
    let attributes: Attributes

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case attributes
    }

    struct Attributes: Codable {
        let latitude: Double
        let longitude: Double
        let radius: Double

        enum CodingKeys: String, CodingKey {
            case latitude
            case longitude
            case radius
        }
    }
}
