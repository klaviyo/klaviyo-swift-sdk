//
// LifecycleEventsExtension.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation
import KlaviyoCore

extension LifeCycleEvents {
    var transformToKlaviyoAction: KlaviyoAction {
        switch self {
        case .terminated:
            return .stop
        case .foregrounded:
            return .start
        case .backgrounded:
            return .stop
        case let .reachabilityChanged(status):
            return .networkConnectivityChanged(status)
        }
    }
}
