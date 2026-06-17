//
//  KlaviyoNotificationDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/13/26.
//

import Foundation
import KlaviyoCore
import OSLog
import UserNotifications

// MARK: - UserNotificationCenterProtocol

/// Abstracts the two `UNUserNotificationCenter` members the proxy needs — delegate
/// assignment and delegate-change observation — so unit tests can supply a lightweight
/// mock without the app-bundle context that `UNUserNotificationCenter.current()` requires.
@MainActor
protocol UserNotificationCenterProtocol: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }

    /// Registers a handler invoked whenever the delegate property changes.
    /// Returns a token whose lifetime controls the observation; release to stop observing.
    func observeDelegate(using handler: @escaping @MainActor () -> Void) -> AnyObject
}

extension UNUserNotificationCenter: UserNotificationCenterProtocol {
    func observeDelegate(using handler: @escaping @MainActor () -> Void) -> AnyObject {
        // KVO for UNUserNotificationCenter.delegate always fires on the main thread.
        // `assumeIsolated` asserts that fact to the type system synchronously (iOS 17+).
        // On earlier OS versions the Task hop is safe: handler is @MainActor-bound
        // (implicitly Sendable) and we don't capture the non-Sendable center here.
        observe(\.delegate, options: [.new]) { _, _ in
            if #available(iOS 17.0, *) {
                MainActor.assumeIsolated { handler() }
            } else {
                Task { @MainActor in handler() }
            }
        }
    }
}

// MARK: - KlaviyoNotificationDelegate

/// A proxy `UNUserNotificationCenterDelegate` that Klaviyo installs as the active
/// notification center delegate when automatic push tracking is enabled.
///
/// The proxy intercepts `didReceive` to fire the `Opened Push` event automatically,
/// then forwards every callback to the delegate that was in place before injection,
/// preserving full host behavior as though the proxy were never there.
///
/// ## Lifecycle
/// `injectIfEnabled()` is called once from `KlaviyoSDK.initialize(with:)`. A change
/// observer on `UNUserNotificationCenter.delegate` re-installs the proxy whenever the
/// host app overwrites it (e.g. in `SceneDelegate.scene(_:willConnectTo:)`), capturing
/// the new value as `existingDelegate`.
///
/// ## Thread safety
/// All mutation is confined to `@MainActor`.
final class KlaviyoNotificationDelegate: NSObject {
    static let shared = KlaviyoNotificationDelegate()

    override private init() {}

    /// The host's delegate captured at injection time, or re-captured on re-installation.
    ///
    /// Weak to mirror `UNUserNotificationCenter.delegate`'s own contract — the proxy
    /// must not silently extend the lifetime of the host delegate object.
    private(set) weak var existingDelegate: (any UNUserNotificationCenterDelegate)?

    /// Retains the delegate-change observation token for the singleton's lifetime.
    ///
    /// Instance property (not `static var`) so it is naturally isolated to `@MainActor`
    /// without requiring `nonisolated(unsafe)` or `@unchecked Sendable` annotations.
    private var centerObservation: AnyObject?

    // MARK: - Forwarding-cycle guard

    private let didReceiveGuard = ForwardingCycleGuard()
    private let willPresentGuard = ForwardingCycleGuard()

    // MARK: - Auto-track guard

    private let autoTrackGuard = BoundedIDSet<String>()

    func markAsAutoTracked(dedupKey: String) { autoTrackGuard.insert(dedupKey) }
    func wasAutoTracked(dedupKey: String) -> Bool { autoTrackGuard.contains(dedupKey) }
    func clearAutoTracked() { autoTrackGuard.clear() }

    // MARK: - Injection

    /// Reads the opt-in flag and notification center from `KlaviyoSwiftEnvironment`,
    /// then installs the proxy when automatic push tracking is enabled.
    ///
    /// Both dependencies are environment-injected so tests can control the plist gate
    /// and substitute a mock center without requiring an app-bundle context.
    ///
    /// Called once from `KlaviyoSDK.initialize(with:)` via
    /// `KlaviyoSwiftEnvironment.injectNotificationDelegate`.
    @MainActor
    static func injectIfEnabled() {
        guard klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled() else {
            if #available(iOS 14.0, *) {
                Logger.notifications.log("Automatic push tracking is off.")
            }
            return
        }

        if #available(iOS 14.0, *) {
            Logger.notifications.info(
                "Injecting notification delegate proxy for automatic push tracking."
            )
        }
        shared.inject(into: klaviyoSwiftEnvironment.notificationCenter())

        if klaviyoSwiftEnvironment.isAutomaticTokenForwardingDisabled() {
            if #available(iOS 14.0, *) {
                Logger.notifications.log("Automatic token forwarding disabled via plist key.")
            }
            return
        }

        if #available(iOS 14.0, *) {
            Logger.notifications.info("Swizzling app delegate for automatic token registration.")
        }
        KlaviyoAppDelegateSwizzler.swizzleIfPossible()
    }

    /// Installs the proxy as the notification center's active delegate and registers
    /// an observer to re-install it if the host later overwrites the delegate property.
    ///
    /// Idempotent: a second call while the proxy is already the active delegate returns
    /// immediately, preventing duplicate observation tokens from accumulating.
    @MainActor
    private func inject(into center: any UserNotificationCenterProtocol) {
        guard center.delegate !== self else { return }

        existingDelegate = center.delegate
        center.delegate = self

        centerObservation = center.observeDelegate { [weak self] in
            guard let self else { return }
            guard center.delegate !== self else { return }
            self.existingDelegate = center.delegate
            center.delegate = self
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension KlaviyoNotificationDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let requestId = response.notification.request.identifier
        let once = OnceCallback(completionHandler)
        guard didReceiveGuard.begin(requestId) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Forwarding cycle detected in didReceive, skipping delegate forward.")
            }
            once()
            return
        }
        defer { didReceiveGuard.end(requestId) }
        let wasTracked = KlaviyoSDK().handle(
            notificationResponse: response,
            withCompletionHandler: { once() }
        )
        if wasTracked && response.actionIdentifier != UNNotificationDismissActionIdentifier {
            markAsAutoTracked(dedupKey: response.klaviyoDedupKey)
        }
        existingDelegate?.userNotificationCenter?(
            center, didReceive: response, withCompletionHandler: { once() }
        )
        once()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable
        (UNNotificationPresentationOptions) -> Void
    ) {
        let requestId = notification.request.identifier
        let once = OnceCallback(completionHandler)
        guard willPresentGuard.begin(requestId) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Forwarding cycle detected in willPresent, skipping delegate forward.")
                once([.list, .banner, .badge, .sound])
            } else {
                once([.alert, .badge, .sound])
            }
            return
        }
        defer { willPresentGuard.end(requestId) }
        existingDelegate?.userNotificationCenter?(
            center, willPresent: notification, withCompletionHandler: { once($0) }
        )
        if #available(iOS 14.0, *) {
            once([.list, .banner, .badge, .sound])
        } else {
            once([.alert, .badge, .sound])
        }
    }
}
