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

class KlaviyoLocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = KlaviyoLocationManager()

    private var locationManager: LocationManagerProtocol

    init(locationManager: LocationManagerProtocol? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()

        super.init()
        self.locationManager.delegate = self
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.startMonitoringSignificantLocationChanges()
    }

    // Q: why do we need this?
    deinit {
        locationManager.delegate = nil
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stopGeofenceMonitoring()
    }

    @MainActor
    func startGeofenceMonitoring() {
        // Q: why does this need to be in the environment/KlaviyoCore?
        guard environment.getLocationAuthorizationStatus() == .authorizedAlways else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("App does not have 'authorizedAlways' permission to access the user's location")
            }
            return
        }

        guard locationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Geofencing is not supported on this device")
            }
            return
        }

        Task {
            // Q: why do we need this. I know you explained in the PR but I don't think I follow.
            guard let apiKey = try? await KlaviyoInternal.fetchAPIKey() else {
                if #available(iOS 14.0, *) {
                    Logger.geoservices.info("SDK is not initialized, skipping geofence refresh")
                }
                return
            }

            await syncGeofences(apiKey: apiKey)
        }
    }

    private func syncGeofences(apiKey: String) async {
        let remoteGeofences = await GeofenceService().fetchGeofences(apiKey: apiKey)
        let activeGeofences = getActiveGeofences()

        let geofencesToRemove = activeGeofences.subtracting(remoteGeofences)
        let geofencesToAdd = remoteGeofences.subtracting(activeGeofences)

        await MainActor.run {
            for geofence in geofencesToAdd {
                locationManager.startMonitoring(for: geofence.toCLCircularRegion())
            }

            let regionsByIdentifier = Dictionary(
                uniqueKeysWithValues: locationManager.monitoredRegions.map { ($0.identifier, $0) }
            )

            for geofence in geofencesToRemove {
                if let clRegion = regionsByIdentifier[geofence.id] {
                    locationManager.stopMonitoring(for: clRegion)
                }
            }
        }
    }

    private func getActiveGeofences() -> Set<Geofence> {
        let geofences = locationManager.monitoredRegions.compactMap { region -> Geofence? in
            guard let circularRegion = region as? CLCircularRegion,
                  let geofence = try? circularRegion.toKlaviyoGeofence() else {
                return nil
            }
            return geofence
        }
        return Set(geofences)
    }

    func stopGeofenceMonitoring() {
        let regions = locationManager.monitoredRegions
        guard !regions.isEmpty else { return }

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("Stopping monitoring for \(regions.count) region(s)")
        }

        regions.forEach(locationManager.stopMonitoring)
    }
}
