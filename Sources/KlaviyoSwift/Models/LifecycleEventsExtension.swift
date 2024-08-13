//
//  LifeCycleEventsExtension.swift
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
        case .forgrounded:
            return .start
        case .backgrounded:
            return .stop
        case let .reachabilityChanged(status):
            return .networkConnectivityChanged(status)
        }
    }
}
