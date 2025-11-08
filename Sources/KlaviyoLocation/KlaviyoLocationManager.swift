//
//  KlaviyoLocationManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/7/24.
//

import Combine
import CoreLocation
import Foundation
import KlaviyoCore
import KlaviyoSwift
import OSLog

class KlaviyoLocationManager: NSObject {
    static let shared = KlaviyoLocationManager()

    private var locationManager: LocationManagerProtocol

    init(locationManager: LocationManagerProtocol? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()

        super.init()
        self.locationManager.delegate = self
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.startMonitoringSignificantLocationChanges()
    }

    deinit {
        locationManager.delegate = nil
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        destroyGeofencing()
    }

    @MainActor
    func setupGeofencing() {
        guard environment.getLocationAuthorizationStatus() == .authorizedAlways else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("App does not have 'authorizedAlways' permission to access the user's location")
            }
            return
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Geofencing is not supported on this device")
            }
            return
        }

        Task {
            guard let apiKey = try? await KlaviyoInternal.fetchAPIKey() else {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("SDK is not initialized, skipping geofence refresh")
                }
                return
            }

            await updateGeofences(apiKey: apiKey)
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

    private func updateGeofences(apiKey: String) async {
        let remoteGeofences = await GeofenceService().fetchGeofences(apiKey: apiKey)
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
                await setupGeofencing()
            }

        case .authorizedWhenInUse, .restricted, .denied, .notDetermined:
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Geofencing not supported on permission level: \(status.description)")
            }
            destroyGeofencing()

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

// MARK: - Data Type Conversions

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
