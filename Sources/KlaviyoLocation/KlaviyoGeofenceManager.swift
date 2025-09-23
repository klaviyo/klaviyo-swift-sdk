//
//  KlaviyoGeofenceManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/7/24.
//

import CoreLocation
import OSLog

internal class KlaviyoGeofenceManager {
    private let locationManager: CLLocationManager

    internal init(locationManager: CLLocationManager) {
        self.locationManager = locationManager
    }

    internal func setupGeofencing() {
        // TODO: Consider factoring permission checks out to its own class
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.info("Geofencing is not supported on this device")
            }
            return
        }

        if #available(iOS 14.0, *) {
            guard locationManager.authorizationStatus == .authorizedAlways else {
                Logger.geoservices.info("App does not have 'authorizedAlways' permission to access the user's location")
                return
            }
        } else {
            guard CLLocationManager.authorizationStatus() == .authorizedAlways else {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("App does not have 'authorizedAlways' permission to access the user's location")
                }
                return
            }
        }

        Task {
            await updateGeofences()
        }
    }

    internal func destroyGeofencing() {
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("Stop monitoring for all regions")
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
                return circularRegion.toKlaviyoGeofence()
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
