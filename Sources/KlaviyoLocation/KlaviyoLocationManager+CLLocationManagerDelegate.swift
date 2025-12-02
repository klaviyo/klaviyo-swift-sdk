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
        @unknown default:
            return
        }
    }

    // MARK: Geofencing

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            await handleGeofenceEvent(region: region, eventType: .geofenceEnter)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            await handleGeofenceEvent(region: region, eventType: .geofenceExit)
        }
    }

    @MainActor
    private func handleGeofenceEvent(region: CLRegion, eventType: Event.EventName.LocationEvent) async {
        guard let region = region as? CLCircularRegion,
              let klaviyoGeofence = try? region.toKlaviyoGeofence(),
              !klaviyoGeofence.companyId.isEmpty else {
            return
        }
        let klaviyoLocationId = klaviyoGeofence.locationId

        // Check cooldown period before processing event
        guard cooldownTracker.isAllowed(geofenceId: klaviyoLocationId, transition: eventType) else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.info("🌎 User \(eventType == .geofenceEnter ? "entered" : "exited", privacy: .public) region \"\(klaviyoLocationId, privacy: .public)\" (cooldown active, skipping)")
            }
            return
        }

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User \(eventType == .geofenceEnter ? "entered" : "exited") region \"\(klaviyoLocationId, privacy: .public)\"")
        }

        // Record the transition to start cooldown period
        cooldownTracker.recordTransition(geofenceId: klaviyoLocationId, transition: eventType)

        let event = Event(
            name: .locationEvent(eventType),
            properties: ["$geofence_id": klaviyoLocationId]
        )

        await KlaviyoInternal.createGeofenceEvent(event: event, for: klaviyoGeofence.companyId)
        if eventType == .geofenceEnter {
            startDwellTimer(for: klaviyoLocationId)
        } else {
            cancelDwellTimer(for: klaviyoLocationId)
        }
    }
}

// MARK: Dwell Timer Management

extension KlaviyoLocationManager {
    private func startDwellTimer(for klaviyoLocationId: String) {
        cancelDwellTimer(for: klaviyoLocationId)
        guard let dwellSeconds = geofenceDwellSettings[klaviyoLocationId] else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.log("Dwell settings have not been specified for region \(klaviyoLocationId). Aborting dwell timer creation.")
            }
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(dwellSeconds), repeats: false) { [weak self] _ in
            self?.handleDwellTimerFired(for: klaviyoLocationId)
        }
        dwellTimers[klaviyoLocationId] = timer

        // Persist timer start time and duration for recovery if app terminates
        dwellTimerTracker.saveTimer(geofenceId: klaviyoLocationId, startTime: environment.date().timeIntervalSince1970, duration: dwellSeconds)

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
        } else {
            if #available(iOS 14.0, *) {
                Logger.geoservices.info("🕐 Attempted to cancel dwell timer for region \(klaviyoLocationId, privacy: .public), but no dwell timer was found for that region")
            }
        }

        dwellTimerTracker.removeTimer(geofenceId: klaviyoLocationId)
    }

    private func handleDwellTimerFired(for klaviyoLocationId: String) {
        dwellTimers.removeValue(forKey: klaviyoLocationId)
        dwellTimerTracker.removeTimer(geofenceId: klaviyoLocationId)
        guard let dwellDuration = geofenceDwellSettings[klaviyoLocationId] else {
            return
        }

        let dwellEvent = Event(
            name: .locationEvent(.geofenceDwell),
            properties: [
                "$geofence_id": klaviyoLocationId,
                "$geofence_dwell_duration": dwellDuration
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: dwellEvent)
            }
        }

        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🕐 Dwell event fired for region \(klaviyoLocationId)")
        }
    }

    /// Check for expired timers and fire dwell events for them
    /// Called on app launch/foreground as a best-effort recovery mechanism
    @MainActor
    func checkExpiredDwellTimers() {
        let expiredTimers = dwellTimerTracker.checkExpiredTimers(activeTimerIds: Set(dwellTimers.keys))

        // Fire dwell events for expired timers
        for (geofenceId, duration) in expiredTimers {
            let dwellEvent = Event(
                name: .locationEvent(.geofenceDwell),
                properties: [
                    "$geofence_id": geofenceId,
                    "$geofence_dwell_duration": duration
                ]
            )

            Task {
                await MainActor.run {
                    KlaviyoInternal.create(event: dwellEvent)
                }
            }

            if #available(iOS 14.0, *) {
                Logger.geoservices.info("🕐 Fired expired dwell event for region \(geofenceId) (expired while app was terminated)")
            }
        }
    }
}
