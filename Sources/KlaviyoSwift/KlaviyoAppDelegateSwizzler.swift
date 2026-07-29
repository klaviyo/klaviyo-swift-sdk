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
/// therefore main-thread-only, but we serialize it through `State`'s `NSLock` so the type
/// stays safely usable from any thread — Swift 6 strict-concurrency-clean without sprinkling
/// `MainActor.assumeIsolated` through the IMP that the Obj-C runtime invokes.
final class KlaviyoAppDelegateSwizzler: NSObject, @unchecked Sendable {
    /// All mutable state lives behind a lock so the compiler can see it as `Sendable`.
    /// Strict-concurrency mode flags raw `static var` declarations as global mutable state —
    /// this wrapper keeps that requirement satisfied without sprinkling `nonisolated(unsafe)`.
    ///
    /// Fields:
    /// - `didSwizzle`: one-way idempotence flag; flipped true the moment swizzling is claimed.
    /// - `didFinishLaunchingObserver`: token for the deferred-install observer; cleared once fired.
    /// - `swappedClasses`: classes where IMPs were exchanged (not just added), so the donor IMP
    ///   knows it should forward to the host's original implementation rather than stop.
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
            // removeObserver is called outside the lock to avoid potential re-entrancy
            // if NotificationCenter tries to acquire the same lock on the same thread.
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

        #if DEBUG
        /// Resets logical swizzle state for test isolation.
        /// ObjC runtime method exchanges are permanent — callers must use a unique class per test.
        func reset() {
            lock.lock()
            didSwizzle = false
            swappedClasses = []
            lock.unlock()
            clearObserver()
        }
        #endif
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
            // `assumeIsolated` asserts main-thread execution synchronously (iOS 17+).
            // On earlier OS versions the Task hop is safe: the queue is .main so the
            // closure already runs on the main thread, and the hop lands on MainActor
            // before any awaited work begins.
            if #available(iOS 17.0, *) {
                MainActor.assumeIsolated {
                    state.clearObserver()
                    guard let delegate = UIApplication.shared.delegate else { return }
                    performSwizzle(on: resolveSwizzleTargetClass(for: delegate))
                }
            } else {
                Task { @MainActor in
                    state.clearObserver()
                    guard let delegate = UIApplication.shared.delegate else { return }
                    performSwizzle(on: resolveSwizzleTargetClass(for: delegate))
                }
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
    static func resolveSwizzleTargetClass(for delegate: any UIApplicationDelegate) -> AnyClass {
        let originalSelector = #selector(
            UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        let initialClass: AnyClass = type(of: delegate)

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
                    Logger.notifications.info("""
                    Swizzler: \(NSStringFromClass(initialClass)) forwards \
                    \(NSStringFromSelector(originalSelector)) to \
                    \(NSStringFromClass(realClass)); swizzling the latter.
                    """)
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

    /// Installs the donor IMP on `hostClass`: exchanges IMPs if the class owns the method,
    /// grafts (adds) if the class has no own implementation (absent or inherited only).
    @MainActor
    private static func performSwizzle(on hostClass: AnyClass) {
        let originalSelector = #selector(
            UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        let swizzledSelector = #selector(
            KlaviyoAppDelegateSwizzler
                .klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )

        guard let donorMethod = class_getInstanceMethod(
            KlaviyoAppDelegateSwizzler.self, swizzledSelector
        ) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.error(
                    "Swizzler donor method missing; device-token forwarding disabled."
                )
            }
            return
        }
        guard state.claimSwizzle() else { return }

        let donorIMP = method_getImplementation(donorMethod)
        let donorTypes = method_getTypeEncoding(donorMethod)

        // Always add the swizzled selector to the host class so we have a stable forwarding target.
        class_addMethod(hostClass, swizzledSelector, donorIMP, donorTypes)

        // Only exchange if hostClass owns the method; class_getInstanceMethod walks the
        // superclass chain and exchanging an inherited IMP mutates the ancestor class.
        if classOwnsMethod(hostClass, selector: originalSelector),
           let hostOriginal = class_getInstanceMethod(hostClass, originalSelector),
           let hostSwizzled = class_getInstanceMethod(hostClass, swizzledSelector) {
            // Own implementation: exchange originalSelector ↔ swizzledSelector.
            method_exchangeImplementations(hostOriginal, hostSwizzled)
            state.insertSwappedClass(ObjectIdentifier(hostClass))
            if #available(iOS 14.0, *) {
                Logger.notifications.info(
                    "Swizzled didRegisterForRemoteNotificationsWithDeviceToken on \(hostClass)."
                )
            }
        } else if let inheritedMethod = class_getInstanceMethod(hostClass, originalSelector),
                  let swizzledMethod = class_getInstanceMethod(hostClass, swizzledSelector) {
            // Inherited implementation: graft donorIMP under originalSelector and redirect
            // swizzledSelector to the inherited IMP so the donor can forward to it.
            method_setImplementation(swizzledMethod, method_getImplementation(inheritedMethod))
            class_addMethod(hostClass, originalSelector, donorIMP, donorTypes)
            state.insertSwappedClass(ObjectIdentifier(hostClass))
            if #available(iOS 14.0, *) {
                Logger.notifications.info(
                    "Grafted (inherited) didRegisterForRemoteNotificationsWithDeviceToken onto \(hostClass)."
                )
            }
        } else {
            // No implementation anywhere — graft donorIMP, no forwarding needed.
            class_addMethod(hostClass, originalSelector, donorIMP, donorTypes)
            if #available(iOS 14.0, *) {
                Logger.notifications.info(
                    "Grafted didRegisterForRemoteNotificationsWithDeviceToken onto \(hostClass)."
                )
            }
        }
    }

    /// Returns `true` if `cls` declares `selector` in its own IMP table, not via superclass.
    private static func classOwnsMethod(_ cls: AnyClass, selector: Selector) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return false }
        defer { free(methods) }
        for i in 0..<Int(count) {
            if method_getName(methods[i]) == selector { return true }
        }
        return false
    }

    #if DEBUG

    // MARK: - Test hooks

    /// Calls `performSwizzle(on:)` directly, bypassing the delegate-availability guard.
    @MainActor
    static func _performSwizzleForTesting(on hostClass: AnyClass) {
        performSwizzle(on: hostClass)
    }

    /// Resets logical swizzle state so each test starts clean.
    static func _resetStateForTesting() { state.reset() }

    static func _isSwappedForTesting(_ identifier: ObjectIdentifier) -> Bool {
        state.isSwapped(identifier)
    }

    /// Exposes the donor selector so tests can inspect the swizzled method table slot
    /// without needing visibility into the private `klaviyo_application` method.
    static var _swizzledSelectorForTesting: Selector {
        #selector(klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
    }
    #endif

    /// Donor method installed onto the host AppDelegate class by `performSwizzle(on:)`.
    /// Invoked by the Obj-C runtime on the main thread when iOS delivers the device-token
    /// callback. Not `@MainActor` — Obj-C dynamic dispatch bypasses Swift actor isolation;
    /// main-thread delivery is guaranteed by the `UIApplicationDelegate` contract instead.
    @objc
    private dynamic func klaviyo_application(
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
            KlaviyoAppDelegateSwizzler
                .klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        guard let method = class_getInstanceMethod(hostClass, swizzledSelector) else { return }
        let hostIMP = method_getImplementation(method)
        typealias DeviceTokenIMP = @convention(c) (NSObject, Selector, UIApplication, NSData) -> Void
        let forwardIMP = unsafeBitCast(hostIMP, to: DeviceTokenIMP.self)
        forwardIMP(self, swizzledSelector, application, deviceToken as NSData)
    }
}
