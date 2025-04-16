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

@MainActor
public struct AppLifeCycleEvents {
    public var lifeCycleEvents: @MainActor (
        (NSNotification.Name) -> AnyPublisher<Notification, Never>,
        @escaping () throws -> Void,
        @escaping () -> Void,
        @escaping () -> Reachability.NetworkStatus?
    ) -> AnyPublisher<LifeCycleEvents, Never>

    public init(lifeCycleEvents: @MainActor @escaping (
        (NSNotification.Name) -> AnyPublisher<Notification, Never>,
        @escaping () throws -> Void,
        @escaping () -> Void,
        @escaping () -> Reachability.NetworkStatus?
    ) -> AnyPublisher<LifeCycleEvents, Never> = { notificationPublisher, startReachability, stopReachability, reachabilityStatus in
        let terminated = notificationPublisher(UIApplication.willTerminateNotification)
            .handleEvents(receiveOutput: { _ in
                stopReachability()
            })
            .map { _ in LifeCycleEvents.terminated }
        let foregrounded = notificationPublisher(UIApplication.didBecomeActiveNotification)
            .handleEvents(receiveOutput: { _ in
                do {
                    try startReachability()
                } catch {
                    // ND: no-op for now...
                }
            })
            .map { _ in LifeCycleEvents.foregrounded }
        let backgrounded = notificationPublisher(UIApplication.didEnterBackgroundNotification)
            .handleEvents(receiveOutput: { _ in
                stopReachability()
            })
            .map { _ in LifeCycleEvents.backgrounded }
        // The below is a bit convoluted since network status can be nil.
        let reachability = notificationPublisher(ReachabilityChangedNotification)
            .receive(on: DispatchQueue.main)
            .compactMap { _ in
                let status = reachabilityStatus() ?? .reachableViaWWAN
                return LifeCycleEvents.reachabilityChanged(status: status)
            }

        return terminated
            .merge(with: reachability)
            .merge(with: foregrounded, backgrounded)
            .handleEvents(receiveSubscription: { _ in
                do {
                    try startReachability()
                } catch {
                    environment.logger.error("failure to start reachability notifier")
                }
            })
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }) {
        self.lifeCycleEvents = lifeCycleEvents
    }

    public static let production = Self()
}
