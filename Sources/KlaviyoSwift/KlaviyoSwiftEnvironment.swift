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
    var pruneCategory: (String) -> Void
    /// Called once from `KlaviyoSDK.initialize(with:)` to conditionally install
    /// `KlaviyoNotificationDelegate` as the active `UNUserNotificationCenter` delegate.
    /// Injected as a closure so tests can stub or assert the call without touching the
    /// real notification center.
    var injectNotificationDelegate: () -> Void
    /// Installs the exact-prior notification-center delegate setter hook.
    /// Split from proxy assignment so tests can use a mock center without mutating runtime classes.
    var installNotificationDelegateHook: @MainActor () -> Void
    /// Installs token interception on the assigned/effective application delegate.
    var installApplicationDelegateTokenHook: @MainActor ((any UIApplicationDelegate)?) -> Void
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
                // `UNUserNotificationCenter.delegate` must be assigned before the app finishes
                // launching. When called on the main thread (the common path from
                // didFinishLaunchingWithOptions), we inject synchronously so the delegate is
                // in place before initialize(with:) returns.
                // On iOS 17+ `assumeIsolated` asserts main-thread execution to the type system.
                // On earlier OS versions we fall back to a Task hop.
                if #available(iOS 17.0, *), Thread.isMainThread {
                    MainActor.assumeIsolated {
                        KlaviyoAutomaticPushInstaller.install(for: UIApplication.shared.delegate)
                    }
                } else {
                    Task { @MainActor in
                        KlaviyoAutomaticPushInstaller.install(for: UIApplication.shared.delegate)
                    }
                }
            },
            installNotificationDelegateHook: {
                KlaviyoNotificationCenterDelegateSwizzler.installIfNeeded()
            },
            installApplicationDelegateTokenHook: { applicationDelegate in
                KlaviyoAppDelegateSwizzler.swizzleIfPossible(on: applicationDelegate)
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
