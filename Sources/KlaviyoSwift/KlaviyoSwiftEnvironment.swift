//
//  KlaviyoSwiftEnvironment.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import Combine
import Foundation
import KlaviyoCore
import UserNotifications

var klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.production

struct KlaviyoSwiftEnvironment {
    var send: (KlaviyoAction) -> Task<Void, Never>?
    var state: () -> KlaviyoState
    var statePublisher: () -> AnyPublisher<KlaviyoState, Never>
    var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    var pruneCategory: (String) -> Void
    /// Called once from `KlaviyoSDK.initialize(with:)` to conditionally install
    /// `KlaviyoNotificationDelegate` as the active `UNUserNotificationCenter` delegate.
    /// Injected as a closure so tests can stub or assert the call without touching the
    /// real notification center.
    var injectNotificationDelegate: () -> Void
    /// Returns whether the host has opted in to automatic push open tracking via the
    /// `klaviyo_automatic_push_open_tracking` Info.plist key.
    /// Injected so tests can enable or disable the feature without modifying `Bundle.main`.
    var isAutomaticPushOpenTrackingEnabled: () -> Bool
    /// Returns whether the host has opted in to automatic device-token forwarding via the
    /// `klaviyo_automatic_push_token_forwarding` Info.plist key. Independent of push tracking; absent
    /// is treated as `false`.
    /// Injected so tests can control the flag without modifying `Bundle.main`.
    var isAutomaticPushTokenForwardingEnabled: () -> Bool
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
            isAutomaticPushOpenTrackingEnabled: {
                Bundle.main.object(
                    forInfoDictionaryKey: SdkFeatures.InfoPlistKey.automaticPushOpenTracking
                ) as? Bool == true
            },
            isAutomaticPushTokenForwardingEnabled: {
                Bundle.main.object(
                    forInfoDictionaryKey: SdkFeatures.InfoPlistKey.automaticPushTokenForwarding
                ) as? Bool == true
            },
            notificationCenter: {
                UNUserNotificationCenter.current()
            }
        )
    }()
}
