//
//  LifecycleEventsExtension.swift
//
//
//  Created by Ajay Subramanya on 8/13/24.
//

import Foundation
import KlaviyoCore

extension LifeCycleEvents {
    var transformToKlaviyoAction: KlaviyoAction {
        switch self {
        case .terminated:
            return .stop
        case .foregrounded:
            print("[KlaviyoSwift] foregrounded")
            return .start
        case .backgrounded:
            print("[KlaviyoSwift] backgrounded")
            return .stop
        case let .reachabilityChanged(status):
            print("[KlaviyoSwift] reachabilityChanged: \(status)")
            return .networkConnectivityChanged(status)
        }
    }
}
