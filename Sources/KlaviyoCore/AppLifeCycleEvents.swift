//
//  AppLifeCycleEvents.swift
//
//
//  Created by Noah Durell on 12/13/22.
//

import Combine
import Foundation
import UIKit

public enum LifeCycleErrors: Error {
    case invalidReachaibilityStatus
}

public enum LifeCycleEvents {
    case terminated
    case foregrounded
    case backgrounded
    case reachabilityChanged(status: Reachability.NetworkStatus)
}

public struct AppLifeCycleEvents {
    public var lifeCycleEvents: () -> AnyPublisher<LifeCycleEvents, Never>

    public init(lifeCycleEvents: @escaping () -> AnyPublisher<LifeCycleEvents, Never> = {
        let terminated = environment
            .notificationCenterPublisher(UIApplication.willTerminateNotification)
            .map { _ in LifeCycleEvents.terminated }
        let foregrounded = environment
            .notificationCenterPublisher(UIApplication.didBecomeActiveNotification)
            .map { _ in LifeCycleEvents.foregrounded }
        let backgrounded = environment
            .notificationCenterPublisher(UIApplication.didEnterBackgroundNotification)
            .map { _ in LifeCycleEvents.backgrounded }
        // The below is a bit convoluted since network status can be nil.
        let reachability = environment
            .notificationCenterPublisher(ReachabilityChangedNotification)
            .compactMap { _ in
                let status = environment.reachabilityStatus() ?? .reachableViaWWAN
                return LifeCycleEvents.reachabilityChanged(status: status)
            }

        return terminated
            .merge(with: reachability)
            .merge(with: foregrounded, backgrounded)
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }) {
        self.lifeCycleEvents = lifeCycleEvents
    }

    package static let production = Self()
}
