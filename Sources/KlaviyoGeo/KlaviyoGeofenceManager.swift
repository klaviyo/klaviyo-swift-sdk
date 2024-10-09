//
//  KlaviyoGeofenceManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/7/24.
//

import CoreLocation
import OSLog
import SwiftUI

public class KlaviyoGeofenceManager {
    private let locationManager: CLLocationManager
    private let geofenceService: GeofenceServiceProvider

    public init(
        locationManager: CLLocationManager = CLLocationManager(),
        geofenceService: GeofenceServiceProvider = GeofenceService()
    ) {
        self.locationManager = locationManager
        self.geofenceService = geofenceService
    }

    func setupGeofencing() {
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

    private func updateGeofences() async {
        let remoteGeofences = await geofenceService.fetchGeofences()
        let activeGeofences = locationManager.monitoredRegions

        let regionsToRemove = activeGeofences.subtracting(remoteGeofences)
        let regionsToAdd = remoteGeofences.subtracting(activeGeofences)

        await MainActor.run {
            for region in regionsToAdd {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("Start monitoring for region \(region.identifier)")
                }
                CLLocationManager().startMonitoring(for: region)
            }

            for region in regionsToRemove {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("Stop monitoring for region \(region.identifier)")
                }
                locationManager.stopMonitoring(for: region)
            }
        }
    }
}
