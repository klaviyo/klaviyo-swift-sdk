//
//  PushBackground.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import UIKit

public enum PushBackground: String, Codable, Sendable {
    case available = "AVAILABLE"
    case restricted = "RESTRICTED"
    case denied = "DENIED"

    public static func create(from status: UIBackgroundRefreshStatus) -> PushBackground {
        switch status {
        case .available:
            return PushBackground.available
        case .restricted:
            return PushBackground.restricted
        case .denied:
            return PushBackground.denied
        @unknown default:
            return PushBackground.available
        }
    }
}
