//
// PushBackground.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import UIKit

public enum PushBackground: String, Codable {
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
