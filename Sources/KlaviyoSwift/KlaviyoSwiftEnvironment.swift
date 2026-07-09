//
//  KlaviyoSwiftEnvironment.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import Combine
import Foundation
import KlaviyoCore
import UIKit
import UserNotifications

var klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.production

struct KlaviyoSwiftEnvironment {
    var send: (KlaviyoAction) -> Task<Void, Never>?
    var state: () -> KlaviyoState
    var statePublisher: () -> AnyPublisher<KlaviyoState, Never>
    var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    var setBadgeCount: (Int) -> Task<Void, Never>?
    var pruneCategory: (String) -> Void
    /// Called once from `KlaviyoSDK.initialize(with:)` to conditionally install
    /// `KlaviyoNotificationDelegate` as the active `UNUserNotificationCenter` delegate.
    /// Injected as a closure so tests can stub or assert the call without touching the
    /// real notification center.
    var injectNotificationDelegate: () -> Void
    /// Returns whether the host has opted in to automatic push open tracking via the
    /// `klaviyo_automatic_push_tracking` Info.plist key.
    /// Injected so tests can enable or disable the feature without modifying `Bundle.main`.
    var isAutomaticPushTrackingEnabled: () -> Bool
    /// Returns whether the host has opted out of automatic token forwarding via the
    /// `klaviyo_disable_automatic_token_forwarding` Info.plist key.
    /// Injected so tests can control the escape hatch without modifying `Bundle.main`.
    var isAutomaticTokenForwardingDisabled: () -> Bool
    /// Provides the notification center for automatic push tracking injection.
    /// Injected so tests can substitute a mock without the app-bundle context that
    /// `UNUserNotificationCenter.current()` requires.
    var notificationCenter: @MainActor () -> any UserNotificationCenterProtocol

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
            },
            pruneCategory: { categoryIdentifier in
                KlaviyoCategoryManager.shared.pruneCategory(categoryIdentifier: categoryIdentifier)
            },
            injectNotificationDelegate: {
                // Dispatched onto the main actor because `UNUserNotificationCenter.delegate`
                // is main-thread-only; `initialize(with:)` may be called from any thread.
                Task { @MainActor in
                    KlaviyoNotificationDelegate.injectIfEnabled()
                }
            },
            isAutomaticPushTrackingEnabled: {
                Bundle.main.object(
                    forInfoDictionaryKey: SdkFeatures.InfoPlistKey.automaticPushTracking
                ) as? Bool == true
            },
            isAutomaticTokenForwardingDisabled: {
                Bundle.main.object(
                    forInfoDictionaryKey: SdkFeatures.InfoPlistKey.disableAutomaticTokenForwarding
                ) as? Bool == true
            },
            notificationCenter: {
                UNUserNotificationCenter.current()
            }
        )
    }()
}
