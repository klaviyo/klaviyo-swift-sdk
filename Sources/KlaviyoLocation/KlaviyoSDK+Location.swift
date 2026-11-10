//
//  KlaviyoSDK+Location.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/27/25.
//

import CoreLocation
import Foundation
import KlaviyoCore

extension KlaviyoSDKModule {
    /// Starts monitoring the geofences configured in your Klaviyo account.
    ///
    /// Call this after initializing `KlaviyoSDK`, typically at launch:
    ///
    /// ```swift
    /// import KlaviyoLocation
    /// import KlaviyoSwift
    ///
    /// KlaviyoSDK()
    ///     .initialize(with: "YOUR_PUBLIC_API_KEY")
    ///     .registerGeofencing()
    /// ```
    ///
    /// When the user enters or exits one of your geofences, the SDK tracks a `$geofence_enter` or
    /// `$geofence_exit` event for the current profile. Repeated transitions for the same geofence
    /// within a short cooldown are skipped.
    ///
    /// Your app's `Info.plist` must include `location` in `UIBackgroundModes`. Without it, this
    /// method crashes, because the SDK enables background location updates.
    ///
    /// Geofencing needs "Always" location authorization with full accuracy. Your app must request
    /// that permission itself; the SDK doesn't prompt. Until it's granted, this method sets nothing
    /// up, and the SDK starts monitoring automatically once the user grants it. If the user later
    /// downgrades the permission, monitoring stops. The geofence list follows the API key, so it
    /// updates if you initialize with a different key.
    ///
    /// The method returns immediately and registers in the background.
    ///
    /// - Returns: The SDK instance, for chaining.
    @discardableResult
    public func registerGeofencing() -> Self {
        Task { @MainActor in
            await KlaviyoLocationManager.shared.startGeofenceMonitoring()
        }

        return self
    }

    /// Stops monitoring Klaviyo geofences.
    ///
    /// The SDK stops monitoring every Klaviyo geofence region and stops observing API key and app
    /// lifecycle changes. Regions your app monitors itself aren't affected. The method returns
    /// immediately and unregisters in the background.
    ///
    /// - Returns: The SDK instance, for chaining.
    @discardableResult
    public func unregisterGeofencing() -> Self {
        Task { @MainActor in
            await KlaviyoLocationManager.shared.stopGeofenceMonitoring()
        }

        return self
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
}
