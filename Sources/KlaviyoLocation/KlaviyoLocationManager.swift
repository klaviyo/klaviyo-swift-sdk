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
    private var lifecycleCancellable: AnyCancellable?
    internal let cooldownTracker = GeofenceCooldownTracker()

    init(locationManager: LocationManagerProtocol? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()

        super.init()
        monitorGeofencesFromBackground()
    }

    func monitorGeofencesFromBackground() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
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
        startObservingAppLifecycle()
    }

    func syncGeofences() async {
        guard let apiKey = try? await KlaviyoInternal.fetchAPIKey() else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.info("SDK is not initialized, skipping geofence refresh")
            }
            return
        }

        guard let location = locationManager.location else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Unable to get current location, skipping geofence refresh")
            }
            return
        }

        let remoteGeofences = await GeofenceService().fetchGeofences(apiKey: apiKey, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let activeGeofences = await getActiveGeofences()

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

    @MainActor
    func getActiveGeofences() async -> Set<Geofence> {
        let geofences = locationManager.monitoredRegions.compactMap { region -> Geofence? in
            guard let circularRegion = region as? CLCircularRegion,
                  circularRegion.isKlaviyoGeofence,
                  let geofence = try? circularRegion.toKlaviyoGeofence() else {
                return nil
            }
            return geofence
        }
        return Set(geofences)
    }

    @MainActor
    func stopGeofenceMonitoring() async {
        stopObservingAPIKeyChanges()
        stopObservingAppLifecycle()
        let klaviyoRegions = locationManager.monitoredRegions
            .compactMap { $0 as? CLCircularRegion }
            .filter(\.isKlaviyoGeofence)
        locationManager.stopMonitoringSignificantLocationChanges()

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

    // MARK: - App Lifecycle Observation

    private func startObservingAppLifecycle() {
        guard lifecycleCancellable == nil else { return }

        lifecycleCancellable = environment.appLifeCycle.lifeCycleEvents()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .terminated:
                    self.locationManager.startMonitoringSignificantLocationChanges()
                case .foregrounded, .backgrounded:
                    self.locationManager.stopMonitoringSignificantLocationChanges()
                default:
                    break
                }
            }
    }

    private func stopObservingAppLifecycle() {
        lifecycleCancellable?.cancel()
        lifecycleCancellable = nil
    }
}
