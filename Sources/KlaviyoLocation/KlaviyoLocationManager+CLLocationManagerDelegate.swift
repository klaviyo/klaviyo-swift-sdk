//
//  KlaviyoLocationManager+CLLocationManagerDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/7/24.
//

import CoreLocation
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog

extension KlaviyoLocationManager: CLLocationManagerDelegate {
    // MARK: Authorization

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if #available(iOS 14.0, *) {
            Logger.geoservices.error("Core Location services error: \(error.localizedDescription)")
        }
    }

    @available(iOS 14.0, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(manager, manager.currentAuthorizationStatus)
    }

    @available(iOS, deprecated: 14.0)
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationChange(manager, status)
    }

    private func handleAuthorizationChange(_ manager: CLLocationManager, _ status: CLAuthorizationStatus) {
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("Core Location authorization status changed. New status: \(status.description)")
        }

        switch status {
        case .authorizedAlways:
            Task {
                await startGeofenceMonitoring()
            }

        case .authorizedWhenInUse, .restricted, .denied, .notDetermined:
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Geofencing not supported on permission level: \(status.description)")
            }
            Task {
                await stopGeofenceMonitoring()
            }
        }
    }

    // MARK: Geofencing

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleGeofenceEvent(region: region, eventType: .geofenceEnter)
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handleGeofenceEvent(region: region, eventType: .geofenceExit)
    }

    private func handleGeofenceEvent(region: CLRegion, eventType: Event.EventName.LocationEvent) {
        guard let region = region as? CLCircularRegion,
              let klaviyoLocationId = region.klaviyoLocationId else {
            return
        }

        // Check cooldown period before processing event
        guard cooldownTracker.isAllowed(geofenceId: klaviyoLocationId, transition: eventType) else {
            if #available(iOS 14.0, *) {
                let action = eventType == .geofenceEnter ? "entered" : "exited"
                Logger.geoservices.info("🌎 User \(action) region \"\(klaviyoLocationId, privacy: .public)\" (cooldown active, skipping)")
            }
            return
        }

        if #available(iOS 14.0, *) {
            let action = eventType == .geofenceEnter ? "entered" : "exited"
            Logger.geoservices.info("🌎 User \(action) region \"\(klaviyoLocationId, privacy: .public)\"")
        }

        // Record the transition to start cooldown period
        cooldownTracker.recordTransition(geofenceId: klaviyoLocationId, transition: eventType)

        let event = Event(
            name: .locationEvent(eventType),
            properties: ["geofence_id": klaviyoLocationId]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: event)
            }
        }
    }
}
