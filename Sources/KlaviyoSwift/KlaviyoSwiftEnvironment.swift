//
//  KlaviyoSwiftEnvironment.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import Combine
import Foundation
import UIKit
import UserNotifications

var klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.production

struct KlaviyoSwiftEnvironment {
    public var send: (KlaviyoAction) -> Task<Void, Never>?
    var state: () -> KlaviyoState
    var statePublisher: () -> AnyPublisher<KlaviyoState, Never>
    var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    var setBadgeCount: (Int) -> Task<Void, Never>?

    static let production: KlaviyoSwiftEnvironment = {
        let store = Store.production

        return KlaviyoSwiftEnvironment(
            send: { action in
                store.send(action)
            },
            state: { store.state.value },
            statePublisher: { store.state.eraseToAnyPublisher() },
            stateChangePublisher: StateChangePublisher().publisher,
            setBadgeCount: { count in
                Task {
                    guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "klaviyo_app_group") as? String,
                          let userDefaults = UserDefaults(suiteName: appGroup) else {
                        return
                    }
                    if #available(iOS 16.0, *) {
                        try? await UNUserNotificationCenter.current().setBadgeCount(count)
                    } else {
                        await MainActor.run {
                            UIApplication.shared.applicationIconBadgeNumber = count
                        }
                    }
                    userDefaults.set(count, forKey: "badgeCount")
                }
            }
        )
    }()
}
