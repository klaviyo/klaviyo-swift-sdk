//
//  KlaviyoGeofenceManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/7/24.
//

import CoreLocation
import KlaviyoCore
import KlaviyoSwift
import OSLog

class KlaviyoGeofenceManager {
    private let locationManager: LocationManagerProtocol

    init(locationManager: LocationManagerProtocol) {
        self.locationManager = locationManager
    }

    func setupGeofencing() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Geofencing is not supported on this device")
            }
            return
        }

        guard environment.getLocationAuthorizationStatus() == .authorizedAlways else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("App does not have 'authorizedAlways' permission to access the user's location")
            }
            return
        }

        Task {
            guard let _ = try? await KlaviyoInternal.fetchAPIKey() else {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("SDK is not initialized, skipping geofence refresh")
                }
                return
            }

            await updateGeofences()
        }
    }

    func destroyGeofencing() {
        if #available(iOS 14.0, *) {
            if !locationManager.monitoredRegions.isEmpty {
                Logger.geoservices.info("Stop monitoring for all regions")
            }
        }
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func updateGeofences() async {
        let remoteGeofences = await GeofenceService().fetchGeofences()
        let activeGeofences: Set<Geofence> = Set(
            locationManager.monitoredRegions.compactMap { region in
                guard let circularRegion = region as? CLCircularRegion else { return nil }
                do {
                    return try circularRegion.toKlaviyoGeofence()
                } catch {
                    if #available(iOS 14.0, *) {
                        Logger.geoservices.error("Failed to convert CLCircularRegion to Geofence: \(error)")
                    }
                    return nil
                }
            }
        )

        let regionsToRemove = activeGeofences.subtracting(remoteGeofences)
        let regionsToAdd = remoteGeofences.subtracting(activeGeofences)

        await MainActor.run {
            for region in regionsToAdd {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("Start monitoring for region \(region.id)")
                }
                locationManager.startMonitoring(for: region.toCLCircularRegion())
            }

            for region in regionsToRemove {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("Stop monitoring for region \(region.id)")
                }
                if let clRegion = locationManager.monitoredRegions.first(where: { $0.identifier == region.id }) {
                    locationManager.stopMonitoring(for: clRegion)
                }
            }
        }
    }
}

// MARK: Data Type Conversions

extension Geofence {
    /// Converts this geofence to a Core Location circular region
    /// - Returns: A CLCircularRegion instance
    func toCLCircularRegion() -> CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: id
        )
        return region
    }
}

extension CLCircularRegion {
    func toKlaviyoGeofence() throws -> Geofence {
        try Geofence(id: identifier, longitude: center.longitude, latitude: center.latitude, radius: radius)
    }

    var klaviyoLocationId: String? {
        do {
            return try toKlaviyoGeofence().locationId
        } catch {
            return nil
        }
    }
}
