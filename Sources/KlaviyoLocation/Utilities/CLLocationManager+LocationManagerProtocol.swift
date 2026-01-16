//
//  CLLocationManager+LocationManagerProtocol.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/24/25.
//

import CoreLocation

// MARK: - Location Manager Protocol

protocol LocationManagerProtocol {
    var location: CLLocation? { get }
    var delegate: CLLocationManagerDelegate? { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    @available(iOS 14.0, *)
    var currentAccuracyAuthorization: CLAccuracyAuthorization { get }
    var currentAuthorizationStatus: CLAuthorizationStatus { get }
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    func isMonitoringAvailable(for regionClass: AnyClass) -> Bool
    var monitoredRegions: Set<CLRegion> { get }
}

// MARK: - CLLocationManager Extension

extension CLLocationManager: LocationManagerProtocol {
    var currentAuthorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return self.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    @available(iOS 14.0, *)
    var currentAccuracyAuthorization: CLAccuracyAuthorization {
        accuracyAuthorization
    }

    func isMonitoringAvailable(for regionClass: AnyClass) -> Bool {
        CLLocationManager.isMonitoringAvailable(for: regionClass)
    }
}
