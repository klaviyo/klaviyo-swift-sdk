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

internal class KlaviyoGeofenceManager {
    private let locationManager: LocationManagerProtocol
    private weak var locationManagerDelegate: KlaviyoLocationManager?

    internal init(locationManager: LocationManagerProtocol) {
        self.locationManager = locationManager
    }

    internal func setLocationManagerDelegate(_ delegate: KlaviyoLocationManager) {
        locationManagerDelegate = delegate
    }

    internal func setupGeofencing() {
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

    internal func destroyGeofencing() {
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
            locationManagerDelegate?.updateDwellSettings(remoteGeofences)
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
