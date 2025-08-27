//
//  CLLocation+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 10/8/24.
//

import CoreLocation

extension CLLocation {
    private var asString: String {
        let latVal: String
        let lonVal: String

        if #available(iOS 15.0, *) {
            latVal = coordinate.latitude.formatted(.number.precision(.fractionLength(4)))
            lonVal = coordinate.longitude.formatted(.number.precision(.fractionLength(4)))
        } else {
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 4

            latVal = formatter.string(from: NSNumber(value: coordinate.latitude)) ?? "unknown"
            lonVal = formatter.string(from: NSNumber(value: coordinate.longitude)) ?? "unknown"
        }

        let latDirection = coordinate.latitude > 0 ? "N" : "S"
        let lonDirection = coordinate.longitude > 0 ? "E" : "W"

        return "\(latVal)º \(latDirection), \(lonVal)º \(lonDirection)"
    }
}
