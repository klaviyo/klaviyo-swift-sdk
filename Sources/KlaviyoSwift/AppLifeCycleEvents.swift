//
//  AppLifeCycleEvents.swift
//  
//
//  Created by Noah Durell on 12/13/22.
//

import Foundation
import Combine
import UIKit



struct AppLifeCycleEvents {
    var lifeCycleEvents: () -> any Publisher<KlaviyoAction, Never> = {
        let terminated = environment
            .notificationCenterPublisher(UIApplication.willTerminateNotification)
            .handleEvents(receiveOutput: { _ in
                environment.stopReachability()
            })
            .map { _ in return KlaviyoAction.stop }
        let foregrounded =  environment
            .notificationCenterPublisher(UIApplication.didBecomeActiveNotification)
            .handleEvents(receiveOutput: { _ in
                do {
                    try environment.startReachability()
                } catch {
                    runtimeWarn("failure to start reachability notifier")
                }
            })
            .map { _ in KlaviyoAction.start }
        let backgrounded = environment
            .notificationCenterPublisher(UIApplication.didEnterBackgroundNotification)
            .handleEvents(receiveSubscription: { _ in
                environment.stopReachability()
            })
            .map { _ in KlaviyoAction.stop }
        let reachability = environment
            .notificationCenterPublisher(Notification.Name("ReachabilityChangedNotification"))
            .flatMap { notification in
                let passthru = PassthroughSubject<KlaviyoAction, Never>()
                guard let reachability = notification.object as? Reachability else {
                    passthru.send(completion: .finished)
                    return passthru
                }
                passthru.send(KlaviyoAction.networkConnectivityChanged(reachability.currentReachabilityStatus))
                passthru.send(completion: .finished)
                return passthru

            }
        return terminated
            .merge(with: reachability)
            .merge(with: foregrounded, backgrounded)
            .receive(on: RunLoop.main)
    }
    
    static let production = Self()
}
