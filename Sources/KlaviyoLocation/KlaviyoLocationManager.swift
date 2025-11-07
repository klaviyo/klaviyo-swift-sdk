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
    private let geofenceManager: KlaviyoGeofenceManager
    private var apiKeyCancellable: AnyCancellable?

    init(locationManager: LocationManagerProtocol? = nil, geofenceManager: KlaviyoGeofenceManager? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()
        self.geofenceManager = geofenceManager ?? KlaviyoGeofenceManager(locationManager: self.locationManager)

        super.init()
        self.locationManager.delegate = self
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.startMonitoringSignificantLocationChanges()
        startObservingAPIKeyChanges()
    }

    deinit {
        stopObservingAPIKeyChanges()
        locationManager.delegate = nil
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        geofenceManager.destroyGeofencing()
    }

    @MainActor
    func setupGeofencing() {
        if environment.getLocationAuthorizationStatus() == .authorizedAlways {
            geofenceManager.setupGeofencing()
        }
    }

    @MainActor
    func destroyGeofencing() {
        geofenceManager.destroyGeofencing()
    }

    // MARK: - API Key Observation

    private func startObservingAPIKeyChanges() {
        guard apiKeyCancellable == nil else { return }
        apiKeyCancellable = KlaviyoInternal.apiKeyPublisher()
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(apiKey):
                    if #available(iOS 14.0, *) {
                        Logger.geoservices.info("🔄 Company ID changed. Updating geofences for new company: \(apiKey)")
                    }
                    geofenceManager.destroyGeofencing()
                    geofenceManager.setupGeofencing()
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
            geofenceManager.setupGeofencing()

        case .authorizedWhenInUse, .restricted, .denied, .notDetermined:
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Geofencing not supported on permission level: \(status.description)")
            }
            geofenceManager.destroyGeofencing()

        default:
            break
        }
    }

    // MARK: Geofencing

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let region = region as? CLCircularRegion,
              let klaviyoGeofence = try? region.toKlaviyoGeofence() else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.info("Received non-Klaviyo geofence notification. Skipping.")
            }
            return
        }

        let klaviyoLocationId = klaviyoGeofence.locationId
        let companyId = klaviyoGeofence.companyId

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
                KlaviyoInternal.createGeofencing(event: enterEvent, apiKey: companyId)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let region = region as? CLCircularRegion,
              let klaviyoGeofence = try? region.toKlaviyoGeofence() else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Received non-Klaviyo geofence notification. Skipping.")
            }
            return
        }

        let klaviyoLocationId = klaviyoGeofence.locationId
        let companyId = klaviyoGeofence.companyId

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
                KlaviyoInternal.createGeofencing(event: exitEvent, apiKey: companyId)
            }
        }
    }
}
