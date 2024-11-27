//
//  KlaviyoSwiftEnvironment.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import Combine
import Foundation
import KlaviyoCore
@_spi(Internals) import KlaviyoSDKDependencies
import UIKit
import UserNotifications

@MainActor var klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.production
@MainActor var store = Store.production

#if swift(<5.10)
@MainActor(unsafe)
#else
@preconcurrency@MainActor
#endif
struct KlaviyoSwiftEnvironment: Sendable {
    var send: @MainActor (KlaviyoAction) -> StoreTask
    var state: @MainActor () -> KlaviyoState
    var statePublisher: @MainActor () -> AnyPublisher<KlaviyoState, Never>
    var stateChangePublisher: @MainActor () -> AsyncStream<KlaviyoState>
    var lifeCyclePublisher: @MainActor () -> AsyncStream<KlaviyoAction>
    var getBackgroundSetting: @MainActor () -> PushBackground
    var networkSession: @MainActor () -> NetworkSession
    var setBadgeCount: @MainActor (Int) -> Void

    static let production: KlaviyoSwiftEnvironment = createProductionInstance()

    @MainActor
    static func createProductionInstance() -> KlaviyoSwiftEnvironment {
        // This instance is created via function to avoid a compiler error
        // Default argument cannot be both main actor-isolated and nonisolated
        // on newer versions of swift it's not necessary to do this.
        KlaviyoSwiftEnvironment(
            send: { action in
                store.send(action)
            },
            state: {
                store.currentState
            },

            statePublisher: {
                store.publisher.eraseToAnyPublisher()
            },
            stateChangePublisher: {
                StateChangePublisher().publisher()
            },
            lifeCyclePublisher: {
                let publisher = AppLifeCycleEvents.production.lifeCycleEvents(
                    environment.notificationCenterPublisher,
                    environment.startReachability, environment.stopReachability,
                    environment.reachabilityStatus).map(\.transformToKlaviyoAction).eraseToAnyPublisher()
                return AsyncStream<KlaviyoAction> { continuation in

                    Task {
                        let cancellableStore = CancellableStore()
                        let cancellable = publisher.sink { value in
                            continuation.yield(value)
                        }
                        
                        Task {
                            await cancellableStore.store(cancellable)
                        }
                        
                        // Handle cancellation
                        continuation.onTermination = { @Sendable _ in
                            Task {
                                await cancellableStore.cancel()
                            }
                        }
                    }
        
                }
            },
            getBackgroundSetting: {
                .create(from: UIApplication.shared.backgroundRefreshStatus)
            },
            networkSession: { createNetworkSession() },
                setBadgeCount: { count in
                       if let userDefaults = UserDefaults(
                           suiteName: Bundle.main.object(
                               forInfoDictionaryKey: "Klaviyo_App_Group")
                               as? String) {
                           if #available(iOS 16.0, *) {
                               UNUserNotificationCenter.current()
                                   .setBadgeCount(count)
                           } else {
                               UIApplication.shared
                                   .applicationIconBadgeNumber = count
                           }
                           userDefaults.set(count, forKey: "badgeCount")
                       }
                }
        )
    }()
}

actor CancellableStore {
    private var cancellable: AnyCancellable?

    func store(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
    }
>>>>>>> d062e0a (Update SDK to support swift 6)
}
