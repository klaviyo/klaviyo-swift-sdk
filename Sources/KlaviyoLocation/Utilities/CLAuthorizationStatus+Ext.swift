//
// CLAuthorizationStatus+Ext.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import CoreLocation

extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            "not determined"
        case .restricted:
            "restricted"
        case .denied:
            "denied"
        case .authorizedAlways:
            "authorized always"
        case .authorizedWhenInUse:
            "authorized when in use"
        case .authorized:
            "authorized"
        @unknown default:
            "(unknown default); rawVavlue \(rawValue)"
        }
    }
}
