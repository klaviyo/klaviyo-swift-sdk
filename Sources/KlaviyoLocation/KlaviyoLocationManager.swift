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
    private var apiKeyCancellable: AnyCancellable?
    internal let cooldownTracker = GeofenceCooldownTracker()

    init(locationManager: LocationManagerProtocol? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()

        super.init()
        monitorGeofencesFromBackground()
    }

    func monitorGeofencesFromBackground() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startMonitoringSignificantLocationChanges()
    }

    @MainActor
    func startGeofenceMonitoring() async {
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
        cooldownTracker.clean()

        await syncGeofences()

        startObservingAPIKeyChanges()
    }

    func syncGeofences() async {
        guard let apiKey = try? await KlaviyoInternal.fetchAPIKey() else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.info("SDK is not initialized, skipping geofence refresh")
            }
            return
        }
        let remoteGeofences = await GeofenceService().fetchGeofences(apiKey: apiKey)
        let activeGeofences = await getActiveGeofences(apiKey)

        let geofencesToRemove = activeGeofences.subtracting(remoteGeofences)
        let geofencesToAdd = remoteGeofences.subtracting(activeGeofences)

        await MainActor.run {
            for geofence in geofencesToAdd {
                locationManager.startMonitoring(for: geofence.toCLCircularRegion())
            }

            let klaviyoRegionsByIdentifier = Dictionary(
                uniqueKeysWithValues: locationManager.monitoredRegions
                    .compactMap { region -> (String, CLCircularRegion)? in
                        guard let circularRegion = region as? CLCircularRegion,
                              circularRegion.isKlaviyoGeofence(apiKey) else {
                            return nil
                        }
                        return (circularRegion.identifier, circularRegion)
                    }
            )

            for geofence in geofencesToRemove {
                if let clRegion = klaviyoRegionsByIdentifier[geofence.id] {
                    locationManager.stopMonitoring(for: clRegion)
                }
            }
        }
    }

    @MainActor
    private func getActiveGeofences(_ apiKey: String) -> Set<Geofence> {
        let geofences = locationManager.monitoredRegions.compactMap { region -> Geofence? in
            guard let circularRegion = region as? CLCircularRegion,
                  circularRegion.isKlaviyoGeofence(apiKey),
                  let geofence = try? circularRegion.toKlaviyoGeofence() else {
                return nil
            }
            return geofence
        }
        return Set(geofences)
    }

    @MainActor
    func getCurrentGeofences() async -> Set<Geofence> {
        guard let apiKey = try? await KlaviyoInternal.fetchAPIKey() else { return [] }
        return getActiveGeofences(apiKey)
    }

    @MainActor
    func stopGeofenceMonitoring() async {
        guard let apiKey = try? await KlaviyoInternal.fetchAPIKey() else { return }
        stopObservingAPIKeyChanges()
        let klaviyoRegions = locationManager.monitoredRegions.compactMap { region -> CLCircularRegion? in
            guard let circularRegion = region as? CLCircularRegion,
                  circularRegion.isKlaviyoGeofence(apiKey) else {
                return nil
            }
            return circularRegion
        }

        guard !klaviyoRegions.isEmpty else { return }

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("Stopping monitoring for \(klaviyoRegions.count) Klaviyo geofence(s)")
        }

        klaviyoRegions.forEach(locationManager.stopMonitoring)
    }

    // MARK: - API Key Observation

    @MainActor
    private func startObservingAPIKeyChanges() {
        guard apiKeyCancellable == nil else { return }
        apiKeyCancellable = KlaviyoInternal.apiKeyPublisher()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(apiKey):
                    if #available(iOS 14.0, *) {
                        Logger.geoservices.info("🔄 Company ID changed. Updating geofences for new company: \(apiKey)")
                    }
                    Task {
                        await self.syncGeofences()
                    }
                case .failure:
                    break
                }
            }
    }

    private func stopObservingAPIKeyChanges() {
        apiKeyCancellable?.cancel()
        apiKeyCancellable = nil
    }
}
