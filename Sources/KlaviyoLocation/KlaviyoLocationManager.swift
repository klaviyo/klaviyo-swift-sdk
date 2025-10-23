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

public class KlaviyoLocationManager: NSObject {
    static let shared = KlaviyoLocationManager()

    private var locationManager: LocationManagerProtocol
    private let geofenceManager: KlaviyoGeofenceManager
    private let geofencePublisher: PassthroughSubject<String, Never> = .init()

    private var geofenceDwellSettings: [String: Int] = [:]
    private var dwellTimers: [String: Timer] = [:]
    private var dwellEnterTimes: [String: Date] = [:]

    internal init(locationManager: LocationManagerProtocol? = nil, geofenceManager: KlaviyoGeofenceManager? = nil) {
        self.locationManager = locationManager ?? CLLocationManager()
        self.geofenceManager = geofenceManager ?? KlaviyoGeofenceManager(locationManager: self.locationManager)

        super.init()
        self.locationManager.delegate = self
        self.locationManager.allowsBackgroundLocationUpdates = true
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
        dwellEnterTimes.removeAll()
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
        guard let region = region as? CLCircularRegion else { return }
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User entered region \"\(region.klaviyoLocationId ?? region.identifier)\"")
        }

        let enterEvent = Event(
            name: .locationEvent(.geofenceEnter),
            properties: [
                "geofence_id": region.klaviyoLocationId
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: enterEvent)
                geofencePublisher.send("Entered \(region.klaviyoLocationId)")
            }
        }

        Task {
            await MainActor.run {
                startDwellTimer(for: region)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let region = region as? CLCircularRegion else { return }
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User exited region \"\(region.klaviyoLocationId ?? region.identifier)\"")
        }

        let exitEvent = Event(
            name: .locationEvent(.geofenceExit),
            properties: [
                "geofence_id": region.klaviyoLocationId
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: exitEvent)
                geofencePublisher.send("Exited \(region.klaviyoLocationId)")
            }
        }

        Task {
            await MainActor.run {
                cancelDwellTimer(for: region)
            }
        }
    }

    // MARK: Dwell Timer Management

    private func startDwellTimer(for region: CLCircularRegion) {
        guard let regionId = region.klaviyoLocationId else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Received unexpected region without a klaviyoLocationId")
            }
            return
        }
        cancelDwellTimer(for: region)
        guard let dwellSeconds = geofenceDwellSettings[regionId] else {
            return
        }

        dwellEnterTimes[regionId] = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(dwellSeconds), repeats: false) { [weak self] _ in
            self?.handleDwellTimerFired(for: regionId)
        }
        dwellTimers[regionId] = timer

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🕐 Started dwell timer for region \(regionId) with \(dwellSeconds) seconds")
        }
    }

    private func cancelDwellTimer(for region: CLCircularRegion) {
        guard let regionId = region.klaviyoLocationId else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.error("Received unexpected region without a klaviyoLocationId")
            }
            return
        }
        if let timer = dwellTimers[regionId] {
            timer.invalidate()
            dwellTimers.removeValue(forKey: regionId)
            dwellEnterTimes.removeValue(forKey: regionId)

            if #available(iOS 14.0, *) {
                Logger.geoservices.info("🕐 Cancelled dwell timer for region \(regionId)")
            }
        }
    }

    private func handleDwellTimerFired(for locationId: String) {
        dwellTimers.removeValue(forKey: locationId)
        dwellEnterTimes.removeValue(forKey: locationId)

        let dwellEvent = Event(
            name: .locationEvent(.geofenceDwell),
            properties: [
                "geofence_id": locationId
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: dwellEvent)
                geofencePublisher.send("Dwelled in \(locationId)")
            }
        }

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🕐 Dwell event fired for region \(locationId)")
        }
    }
}
