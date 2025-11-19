//
//  KlaviyoSDK+Location.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/27/25.
//

import CoreLocation
import Foundation
import KlaviyoSwift

extension KlaviyoSDK {
    /// Registers app for geofencing. Geofencing will only be set up when "authorized always" permission level is granted.
    /// App will begin listening for geofence events (enter, exit, dwell) according to the geofences configured in your Klaviyo account.
    @MainActor
    public func registerGeofencing() async {
        await KlaviyoLocationManager.shared.startGeofenceMonitoring()
    }

    /// To be called in didFinishLaunchingWithOptions to ensure geofence events that happen in a backgrounded/terminated state are processed.
    public func monitorGeofencesFromBackground() {
        KlaviyoLocationManager.shared.monitorGeofencesFromBackground()
    }

    /// Unregisters app for geofencing. Stops monitoring for geofences and cleans up resources.
    @MainActor
    public func unregisterGeofencing() async {
        await KlaviyoLocationManager.shared.stopGeofenceMonitoring()
    }

    /// Returns the current geofence regions being monitored by Klaviyo SDK
    ///
    /// This method is for internal use only and should not be used in production applications.
    /// It provides the same functionality as ``CLLocationManager.monitoredRegions``
    @MainActor
    @_spi(KlaviyoPrivate)
    @available(*, deprecated, message: "This function is for internal use only, and should not be used in production applications")
    public func getCurrentGeofences() async -> Set<CLCircularRegion> {
        await Set(KlaviyoLocationManager.shared.getActiveGeofences().map { $0.toCLCircularRegion() })
    }

    // TODO: add documentation
    @MainActor
    @_spi(KlaviyoPrivate)
    @available(*, deprecated, message: "This function is for internal use only, and should not be used in production applications")
    public func onGeofenceEvent(_ action: () -> Void) {
        // TODO: implement handler
    }
}
