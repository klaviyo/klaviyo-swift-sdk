//
// PushEnablement.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import UIKit

public enum PushEnablement: String, Codable {
    case notDetermined = "NOT_DETERMINED"
    case denied = "DENIED"
    case authorized = "AUTHORIZED"
    case provisional = "PROVISIONAL"
    case ephemeral = "EPHEMERAL"

    public static func create(from status: UNAuthorizationStatus) -> PushEnablement {
        switch status {
        case .denied:
            return PushEnablement.denied
        case .authorized:
            return PushEnablement.authorized
        case .provisional:
            return PushEnablement.provisional
        case .ephemeral:
            return PushEnablement.ephemeral
        default:
            return PushEnablement.notDetermined
        }
    }
}
