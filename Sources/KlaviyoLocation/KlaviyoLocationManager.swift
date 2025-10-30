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
import UIKit

public class KlaviyoLocationManager: NSObject {
    public static let shared = KlaviyoLocationManager()

    private var locationManager: LocationManagerProtocol
    private let geofenceManager: KlaviyoGeofenceManager
    private let geofencePublisher: PassthroughSubject<String, Never> = .init()

    private var geofenceDwellSettings: [String: Int] = [:]
    private var dwellTimers: [String: Timer] = [:]

    internal init(locationManager: LocationManagerProtocol? = nil, geofenceManager: KlaviyoGeofenceManager? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()
        self.geofenceManager = geofenceManager ?? KlaviyoGeofenceManager(locationManager: self.locationManager)

        super.init()
        self.locationManager.delegate = self
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.startMonitoringSignificantLocationChanges()
        self.geofenceManager.setLocationManagerDelegate(self)
    }

    deinit {
        locationManager.delegate = nil
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        geofenceManager.destroyGeofencing()

        for timer in dwellTimers.values {
            timer.invalidate()
        }
        dwellTimers.removeAll()
        geofenceDwellSettings.removeAll()
    }

    @MainActor
    internal func setupGeofencing() {
        if environment.getLocationAuthorizationStatus() == .authorizedAlways {
            geofenceManager.setupGeofencing()
        }
    }

    @MainActor
    internal func destroyGeofencing() {
        geofenceManager.destroyGeofencing()
    }

    internal func updateDwellSettings(_ geofences: Set<Geofence>) {
        geofenceDwellSettings.removeAll()
        for geofence in geofences {
            geofenceDwellSettings[geofence.locationId] = geofence.dwell
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
              let klaviyoLocationId = region.klaviyoLocationId else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.warning("Received non-Klaviyo geofence notification. Skipping.")
            }
            return
        }
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User entered region \"\(klaviyoLocationId)\"")
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
                geofencePublisher.send("Entered \(klaviyoLocationId)")
            }
        }

        Task {
            await MainActor.run {
                startDwellTimer(for: klaviyoLocationId)
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
            Logger.geoservices.info("🌎 User exited region \"\(klaviyoLocationId)\"")
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
                geofencePublisher.send("Exited \(klaviyoLocationId)")
            }
        }

        Task {
            await MainActor.run {
                cancelDwellTimer(for: klaviyoLocationId)
            }
        }
    }

    // MARK: Dwell Timer Management

    private func startDwellTimer(for klaviyoLocationId: String) {
        cancelDwellTimer(for: klaviyoLocationId)
        guard let dwellSeconds = geofenceDwellSettings[klaviyoLocationId] else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(dwellSeconds), repeats: false) { [weak self] _ in
            self?.handleDwellTimerFired(for: klaviyoLocationId)
        }
        dwellTimers[klaviyoLocationId] = timer

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🕐 Started dwell timer for region \(klaviyoLocationId) with \(dwellSeconds) seconds")
        }
    }

    private func cancelDwellTimer(for klaviyoLocationId: String) {
        if let timer = dwellTimers[klaviyoLocationId] {
            timer.invalidate()
            dwellTimers.removeValue(forKey: klaviyoLocationId)

            if #available(iOS 14.0, *) {
                Logger.geoservices.info("🕐 Cancelled dwell timer for region \(klaviyoLocationId)")
            }
        }
    }

    private func handleDwellTimerFired(for klaviyoLocationId: String) {
        dwellTimers.removeValue(forKey: klaviyoLocationId)

        let dwellEvent = Event(
            name: .locationEvent(.geofenceDwell),
            properties: [
                "geofence_id": klaviyoLocationId
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: dwellEvent)
                geofencePublisher.send("Dwelled in \(klaviyoLocationId)")
            }
        }

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🕐 Dwell event fired for region \(klaviyoLocationId)")
        }
    }
}
