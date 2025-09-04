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

    public init(locationManager: CLLocationManager) {
        self.locationManager = locationManager
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

    func destroyGeofencing() {
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("Stop monitoring for all regions")
        }
        let activeGeofences = locationManager.monitoredRegions
        for region in activeGeofences {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func updateGeofences() async {
        let remoteGeofences = await GeofenceService().fetchGeofences()
        let activeGeofences = locationManager.monitoredRegions

        let regionsToRemove = activeGeofences.subtracting(remoteGeofences)
        let regionsToAdd = remoteGeofences.subtracting(activeGeofences)

        await MainActor.run {
            for region in regionsToAdd {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("Start monitoring for region \(region.identifier)")
                }
                locationManager.startMonitoring(for: region)
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

// TODO: Implement this
// See this: https://forums.developer.apple.com/forums/thread/757002
// if #available(iOS 17.0, *) {
//    Task {
//        // Create a custom monitor.
//        let monitor = await CLMonitor("my_custom_monitor")
//        // Register the condition for 200 meters.
//        let center1 = CLLocationCoordinate2D(latitude: 72, longitude: -120);
//        let condition = CLMonitor.CircularGeographicCondition(center: center1, radius: 100)
//        // Add the condition to the monitor.
//        await monitor.add(condition, identifier: "stay_within_200_meters")
//        // Start monitoring.
//        for try await event in await monitor.events {
//            // Respond to events.
//            if event.state == .satisfied {
//                // Process the 200 meter condition.
//            }
//        }
//    }
// }

// Start monitoring
// if #available(iOS 17.0, *) {
//    Task {
//        let locationMontior: CLMonitor = await .init("geofence monitor")
//        let condition = CLMonitor.CircularGeographicCondition(center: regionCoordinate, radius: 200)
//        await locationMontior.add(condition, identifier: "place1", assuming: CLMonitor.Event.State.satisfied)
//    }
// } else {
//    locationManager.startMonitoring(for: geofenceRegion)
// }
