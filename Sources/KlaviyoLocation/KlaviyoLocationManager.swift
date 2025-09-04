//
//  KlaviyoLocationManager.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/7/24.
//

import Combine
import CoreLocation
import Foundation
import KlaviyoSwift
import OSLog

public class KlaviyoLocationManager: NSObject {
    static let shared = KlaviyoLocationManager()

    private let locationManager = CLLocationManager()
    private let geofenceManager: KlaviyoGeofenceManager
    public let geofencePublisher: PassthroughSubject<String, Never> = .init()

    override public init() {
        geofenceManager = KlaviyoGeofenceManager(locationManager: locationManager)
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
    }

    @MainActor
    public func setupGeofencing() {
        if #available(iOS 14.0, *) {
            if locationManager.authorizationStatus == .authorizedAlways {
                geofenceManager.setupGeofencing()
            }
        } else {
            // TODO: pre-iOS-14 implmentation
        }
    }

    @MainActor
    public func destroyGeofencing() {
        geofenceManager.destroyGeofencing()
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
        handleCLAuthorizationStatusChange(manager, manager.authorizationStatus)
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

        case .authorizedWhenInUse:
            break

        case .restricted, .denied:
            // TODO: disable location features
            break

        case .notDetermined:
            break

        default:
            break
        }
    }

    // MARK: Geofencing

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let region = region as? CLCircularRegion else { return }
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User entered region \"\(region.identifier)\"")
        }

        let enterEvent = Event(
            name: .locationEvent(.enteredBoundary),
            properties: [
                "boundaryIdentifier": region.identifier
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: enterEvent)
                geofencePublisher.send("Entered \(region.identifier)")
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let region = region as? CLCircularRegion else { return }
        if #available(iOS 14.0, *) {
            Logger.geoservices.info("🌎 User exited region \"\(region.identifier)\"")
        }

        let exitEvent = Event(
            name: .locationEvent(.exitedBoundary),
            properties: [
                "boundaryIdentifier": region.identifier
            ]
        )

        Task {
            await MainActor.run {
                KlaviyoInternal.create(event: exitEvent)
                geofencePublisher.send("Exited \(region.identifier)")
            }
        }
    }
}
