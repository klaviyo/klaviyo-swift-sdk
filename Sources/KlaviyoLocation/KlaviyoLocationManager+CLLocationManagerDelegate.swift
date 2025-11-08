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
        handleCLAuthorizationStatusChange(manager, locationManager.currentAuthorizationStatus)
    }

    @available(iOS, deprecated: 14.0)
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleCLAuthorizationStatusChange(manager, status)
    }

    private func handleCLAuthorizationStatusChange(_ manager: CLLocationManager, _ status: CLAuthorizationStatus) {
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
            stopGeofenceMonitoring()

        default:
            break
        }
    }

    // MARK: Geofencing

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let region = region as? CLCircularRegion,
              let klaviyoLocationId = region.klaviyoLocationId else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.info("Received non-Klaviyo geofence notification. Skipping.")
            }
            return
        }
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User entered region \"\(klaviyoLocationId, privacy: .public)\"")
        }

        let enterEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: [
                "geofence_id": klaviyoLocationId
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: enterEvent)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let region = region as? CLCircularRegion,
              let klaviyoLocationId = region.klaviyoLocationId else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Received non-Klaviyo geofence notification. Skipping.")
            }
            return
        }
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User exited region \"\(klaviyoLocationId, privacy: .public)\"")
        }

        let exitEvent = Event(
            name: .locationEvent(.geofenceExit),
            properties: [
                "geofence_id": klaviyoLocationId
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: exitEvent)
            }
        }
    }
}
