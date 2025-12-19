//
//  CLAuthorizationStatus+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/8/24.
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
