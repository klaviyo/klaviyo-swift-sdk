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
    case forgrounded
    case backgrounded
    case reachabilityChanged(status: Reachability.NetworkStatus)
}

public struct AppLifeCycleEvents {
    public var lifeCycleEvents: () -> AnyPublisher<LifeCycleEvents, Never> = {
        let terminated = environment
            .notificationCenterPublisher(UIApplication.willTerminateNotification)
            .handleEvents(receiveOutput: { _ in
                environment.stopReachability()
            })
            .map { _ in LifeCycleEvents.terminated }
        let foregrounded = environment
            .notificationCenterPublisher(UIApplication.didBecomeActiveNotification)
            .handleEvents(receiveOutput: { _ in
                do {
                    try environment.startReachability()
                } catch {
                    environment.emitDeveloperWarning("failure to start reachability notifier")
                }
            })
            .map { _ in LifeCycleEvents.forgrounded }
        let backgrounded = environment
            .notificationCenterPublisher(UIApplication.didEnterBackgroundNotification)
            .handleEvents(receiveOutput: { _ in
                environment.stopReachability()
            })
            .map { _ in LifeCycleEvents.backgrounded }
        // The below is a bit convoluted since network status can be nil.
        let reachability = environment
            .notificationCenterPublisher(ReachabilityChangedNotification)
            .map { _ in
                // TODO: compact map isn't working, need to fix
                let status = environment.reachabilityStatus() ?? .reachableViaWWAN
                return LifeCycleEvents.reachabilityChanged(status: status)
            }

        return terminated
            .merge(with: reachability)
            .merge(with: foregrounded, backgrounded)
            .handleEvents(receiveSubscription: { _ in
                do {
                    try environment.startReachability()
                } catch {
                    environment.emitDeveloperWarning("failure to start reachability notifier")
                }
            })
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    static let production = Self()
}
