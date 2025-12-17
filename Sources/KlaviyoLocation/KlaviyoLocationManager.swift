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
    let cooldownTracker = GeofenceCooldownTracker()
    var geofenceService: GeofenceServiceProvider

    init(locationManager: LocationManagerProtocol? = nil, geofenceService: GeofenceServiceProvider? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()
        self.geofenceService = geofenceService ?? GeofenceService()

        super.init()
        self.locationManager.delegate = self
        self.locationManager.allowsBackgroundLocationUpdates = true
    }

    @MainActor
    func startGeofenceMonitoring() async {
        guard environment.getLocationAuthorizationStatus() == .authorizedAlways else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("App does not have 'authorizedAlways' permission to access the user's location")
            }
            await stopGeofenceMonitoring()
            return
        }

        if #available(iOS 14.0, *) {
            guard locationManager.currentAccuracyAuthorization == .fullAccuracy else {
                Logger.geoservices.warning("App does not have full accuracy permission to access the user's location")
                await stopGeofenceMonitoring()
                return
            }
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

        // Calculate available spots for geofences based on iOS limit
        let activeGeofences = await getActiveGeofences()
        let availableSpots = 20 - locationManager.monitoredRegions.count + activeGeofences.count

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("📊 Available spots for geofences: \(availableSpots)")
        }

        let (latitude, longitude) = transformCoordinates(locationManager.location?.coordinate)
        var remoteGeofences = await geofenceService.fetchGeofences(apiKey: apiKey, latitude: latitude, longitude: longitude)

        // Filter to nearest geofences if location is available
        if let latitude, let longitude {
            let nearestGeofences = GeofenceDistanceCalculator.filterToNearest(
                geofences: remoteGeofences,
                userLatitude: locationManager.location?.coordinate.latitude ?? latitude,
                userLongitude: locationManager.location?.coordinate.longitude ?? longitude,
                limit: availableSpots
            )
            remoteGeofences = Set(nearestGeofences)
        }

        let geofencesToRemove = activeGeofences.subtracting(remoteGeofences)
        let geofencesToAdd = remoteGeofences.subtracting(activeGeofences)
        if #available(iOS 14.0, *) {
            Logger.geoservices.warning("⚠️ Adding \(geofencesToAdd.count) and removing \(geofencesToRemove.count) geofences")
        }

        await MainActor.run {
            // Only look up Klaviyo geofences to ensure we never affect non-Klaviyo regions
            let regionsByIdentifier = Dictionary(
                uniqueKeysWithValues: locationManager.monitoredRegions
                    .compactMap { $0 as? CLCircularRegion }
                    .filter(\.isKlaviyoGeofence)
                    .map { ($0.identifier, $0) }
            )
            for geofence in geofencesToRemove {
                if let clRegion = regionsByIdentifier[geofence.id] {
                    locationManager.stopMonitoring(for: clRegion)
                }
            }
            for geofence in geofencesToAdd {
                locationManager.startMonitoring(for: geofence.toCLCircularRegion())
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

    // MARK: - Coordinate Transformation

    /// Transforms coordinates by rounding to the nearest 0.145 degrees (~10 mile precision)
    /// and clamping to valid coordinate ranges.
    ///
    /// The result is truncated to 3 decimal places to avoid long repeating decimals.
    ///
    /// - Parameter coordinate: The original coordinate to transform
    /// - Returns: A tuple containing the transformed (latitude, longitude) coordinates truncated to 3 decimal places
    private func transformCoordinates(_ coordinate: CLLocationCoordinate2D?) -> (latitude: Double?, longitude: Double?) {
        guard let coordinate else { return (nil, nil) }
        // Round coordinates to nearest 0.145 degrees (~10 mile precision)
        let coordinatePrecision = 0.145
        let roundedLatitude = round(coordinate.latitude / coordinatePrecision) * coordinatePrecision
        let roundedLongitude = round(coordinate.longitude / coordinatePrecision) * coordinatePrecision

        // Truncate to 3 decimal places to avoid long repeating decimals
        let truncatedLatitude = trunc(roundedLatitude * 1000) / 1000
        let truncatedLongitude = trunc(roundedLongitude * 1000) / 1000

        // Clamp coordinates to valid ranges
        let clampedLatitude = max(-90.0, min(90.0, truncatedLatitude))
        let clampedLongitude = max(-180.0, min(180.0, truncatedLongitude))

        return (latitude: clampedLatitude, longitude: clampedLongitude)
    }
}
