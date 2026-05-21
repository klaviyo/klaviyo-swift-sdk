//
//  KlaviyoAppDelegateSwizzler.swift
//  klaviyo-swift-sdk
//
//  Swizzles `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` on the host
//  app delegate so the SDK receives push tokens automatically.
//
//  Created by Glenn Brannelly on 5/15/26.
//

import Foundation
import ObjectiveC.runtime
import OSLog
import UIKit

/// Donor class whose `klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
/// IMP is grafted onto the host app's `UIApplicationDelegate` class at runtime so the SDK
/// receives device tokens without the host having to call `KlaviyoSDK().set(pushToken:)`.
///
/// ## Concurrency model
///
/// Swizzling entry points (`swizzleIfPossible()`, `performSwizzle(on:)`) are invoked from
/// `KlaviyoNotificationDelegate.injectIfEnabled()`, which is `@MainActor`. The grafted IMP
/// (`klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`) is fired by
/// iOS on the main thread per the `UIApplicationDelegate` contract. All state mutation is
/// therefore main-thread-only, but we serialize it through `stateLock` so the type stays
/// safely usable from any thread — Swift 6 strict-concurrency-clean without sprinkling
/// `MainActor.assumeIsolated` through the IMP that the Obj-C runtime invokes.
@objc final class KlaviyoAppDelegateSwizzler: NSObject, @unchecked Sendable {
    /// All mutable state lives behind a lock so the compiler can see it as `Sendable`.
    /// Each accessor below grabs the lock for a single read or write. Strict-concurrency
    /// mode flags raw `static var` declarations as global mutable state — this wrapper is
    /// how we keep that requirement satisfied without sprinkling `nonisolated(unsafe)`.
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var didSwizzle = false
        private var didFinishLaunchingObserver: NSObjectProtocol?
        private var swappedClasses: Set<ObjectIdentifier> = []

        var swizzled: Bool {
            lock.lock(); defer { lock.unlock() }
            return didSwizzle
        }

        var hasObserver: Bool {
            lock.lock(); defer { lock.unlock() }
            return didFinishLaunchingObserver != nil
        }

        /// Atomically transition `didSwizzle` from false → true and report whether this caller
        /// is the one that did it. Used by `performSwizzle(on:)` to avoid double-swizzling.
        func claimSwizzle() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !didSwizzle else { return false }
            didSwizzle = true
            return true
        }

        func setObserver(_ observer: NSObjectProtocol?) {
            lock.lock(); defer { lock.unlock() }
            didFinishLaunchingObserver = observer
        }

        func clearObserver() {
            lock.lock()
            let observer = didFinishLaunchingObserver
            didFinishLaunchingObserver = nil
            lock.unlock()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func insertSwappedClass(_ identifier: ObjectIdentifier) {
            lock.lock(); defer { lock.unlock() }
            swappedClasses.insert(identifier)
        }

        func isSwapped(_ identifier: ObjectIdentifier) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return swappedClasses.contains(identifier)
        }
    }

    private static let state = State()

    /// Swizzles the device-token method on `UIApplication.shared.delegate`'s class. If the
    /// delegate is not yet available (rare; possible if the SDK is initialized very early in
    /// app launch), defers until `UIApplication.didFinishLaunchingNotification` fires.
    @MainActor
    static func swizzleIfPossible() {
        if state.swizzled { return }

        if let delegate = UIApplication.shared.delegate {
            performSwizzle(on: resolveSwizzleTargetClass(for: delegate))
            return
        }

        // Guard against duplicate registration if `swizzleIfPossible()` is called more than
        // once before `didFinishLaunchingNotification` fires (e.g., host calls
        // `KlaviyoSDK().initialize(with:)` twice in `application(_:willFinishLaunching...)`).
        // Without this, the second call would register a second observer that stays alive in
        // `NotificationCenter` indefinitely — `state.setObserver(...)` would overwrite the
        // stored token, losing the first reference and leaking it.
        if state.hasObserver { return }

        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                state.clearObserver()
                guard let delegate = UIApplication.shared.delegate else { return }
                performSwizzle(on: resolveSwizzleTargetClass(for: delegate))
            }
        }
        state.setObserver(observer)
    }

    /// Returns the class on which we should swizzle the device-token method.
    ///
    /// For most hosts this is just `type(of: delegate)`. For SwiftUI hosts using
    /// `@UIApplicationDelegateAdaptor`, however, `UIApplication.shared.delegate` is Apple's
    /// private `SwiftUI.AppDelegate` wrapper — it doesn't actually implement the
    /// `UIApplicationDelegate` selectors in its IMP table; it forwards them to the host's real
    /// `AppDelegate` via Obj-C dynamic dispatch (`-forwardingTargetForSelector:`). Swizzling
    /// the wrapper grafts our IMP onto a class that has no original method to forward to —
    /// `UIApplication.shared.delegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// would hit our IMP and stop there, never invoking the host's own implementation.
    ///
    /// To preserve the host's implementation, we probe `-forwardingTargetForSelector:` for the
    /// `didRegister` selector. If the delegate returns a non-nil object whose class actually
    /// implements the method, we swizzle that class instead so the Obj-C runtime's forwarding
    /// chain delivers the call to our IMP on the real implementor. If the probe returns nil
    /// (host doesn't use a forwarding proxy, or uses `-forwardInvocation:` style forwarding
    /// instead), we fall back to the wrapper class. The SDK still receives the token; only
    /// the host's own method is bypassed in that fallback.
    @MainActor
    private static func resolveSwizzleTargetClass(for delegate: any UIApplicationDelegate) -> AnyClass {
        let originalSelector = #selector(
            UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        let initialClass: AnyClass = type(of: delegate)

        // If the initial class implements the method directly, swizzle there.
        if class_getInstanceMethod(initialClass, originalSelector) != nil {
            return initialClass
        }

        // Forwarding-proxy fast path: ask Obj-C runtime where this selector would actually
        // dispatch via `-forwardingTargetForSelector:`. Used by SwiftUI's
        // `@UIApplicationDelegateAdaptor` wrapper, and any other proxy that follows the same
        // convention.
        if let nsDelegate = delegate as? NSObject,
           let forwardingTarget = nsDelegate.forwardingTarget(for: originalSelector) {
            let realClass: AnyClass = type(of: forwardingTarget as AnyObject)
            if realClass !== initialClass,
               class_getInstanceMethod(realClass, originalSelector) != nil {
                if #available(iOS 14.0, *) {
                    Logger.notifications.info("Klaviyo swizzler: \(NSStringFromClass(initialClass)) forwards \(NSStringFromSelector(originalSelector)) to \(NSStringFromClass(realClass)); swizzling the latter.")
                }
                return realClass
            }
        }

        // Initial class has no IMP and either no forwarding target or one whose class also
        // doesn't implement the method. Fall back to the initial class — the swizzler will
        // graft our IMP on it. The SDK still gets the token, but the host's own method
        // (if reachable through some other forwarding mechanism) won't fire.
        return initialClass
    }

    /// Test-only hook into `resolveSwizzleTargetClass(for:)`. Internal callers should use the
    /// private function directly via `swizzleIfPossible()`; this exists so the unit-test target
    /// can validate the forwarding-target resolution without going through the full swizzling
    /// flow (which mutates global runtime state).
    @MainActor
    static func testHook_resolveSwizzleTargetClass(for delegate: any UIApplicationDelegate) -> AnyClass {
        resolveSwizzleTargetClass(for: delegate)
    }

    @MainActor
    private static func performSwizzle(on hostClass: AnyClass) {
        guard state.claimSwizzle() else { return }

        let originalSelector = #selector(
            UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        let swizzledSelector = #selector(
            KlaviyoAppDelegateSwizzler.klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )

        guard let donorMethod = class_getInstanceMethod(KlaviyoAppDelegateSwizzler.self, swizzledSelector) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.error("Klaviyo swizzler donor method missing; device-token forwarding disabled.")
            }
            return
        }
        let donorIMP = method_getImplementation(donorMethod)
        let donorTypes = method_getTypeEncoding(donorMethod)

        // Always add the swizzled selector to the host class so we have a stable forwarding target.
        class_addMethod(hostClass, swizzledSelector, donorIMP, donorTypes)

        if let hostOriginal = class_getInstanceMethod(hostClass, originalSelector),
           let hostSwizzled = class_getInstanceMethod(hostClass, swizzledSelector) {
            // Host implements the original — exchange so calls to the original selector hit our
            // IMP, and our forwarding call (swizzled selector) hits the host's original IMP.
            method_exchangeImplementations(hostOriginal, hostSwizzled)
            state.insertSwappedClass(ObjectIdentifier(hostClass))
            if #available(iOS 14.0, *) {
                Logger.notifications.info("Klaviyo swizzled didRegisterForRemoteNotificationsWithDeviceToken on \(hostClass).")
            }
        } else {
            // Host does not implement the method — graft our IMP under the original selector
            // directly. No forwarding required (there is no original to call).
            class_addMethod(hostClass, originalSelector, donorIMP, donorTypes)
            if #available(iOS 14.0, *) {
                Logger.notifications.info("Klaviyo grafted didRegisterForRemoteNotificationsWithDeviceToken onto \(hostClass).")
            }
        }
    }

    /// Grafted IMP. Invoked by the Obj-C runtime on the main thread when iOS delivers the
    /// device-token callback to the host's AppDelegate. Not `@MainActor` because it's called
    /// through dynamic dispatch by Obj-C, which doesn't know about Swift actor isolation.
    /// Swift access is `private` because the only legitimate callers are the Obj-C runtime
    /// (via the grafted/exchanged IMP table on the host's delegate class) and `performSwizzle`
    /// in this same class (via `#selector(...)`); `@objc` still exposes it for both paths.
    @objc private dynamic func klaviyo_application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        KlaviyoSDK().set(pushToken: deviceToken)

        // Only forward if we exchanged with an existing host IMP. If we merely grafted our IMP
        // (host didn't implement the method), the swizzled selector points back at us and
        // forwarding would recurse.
        let hostClass: AnyClass = type(of: self)
        guard Self.state.isSwapped(ObjectIdentifier(hostClass)) else { return }

        let swizzledSelector = #selector(
            KlaviyoAppDelegateSwizzler.klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        guard let method = class_getInstanceMethod(hostClass, swizzledSelector) else { return }
        let imp = method_getImplementation(method)
        typealias DeviceTokenIMP = @convention(c) (NSObject, Selector, UIApplication, NSData) -> Void
        let fn = unsafeBitCast(imp, to: DeviceTokenIMP.self)
        fn(self, swizzledSelector, application, deviceToken as NSData)
    }

}
