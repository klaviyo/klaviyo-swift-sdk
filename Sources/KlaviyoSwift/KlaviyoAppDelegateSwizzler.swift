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
/// Swizzling entry points (`swizzleIfPossible(on:)`, `performSwizzle(on:)`) are invoked from
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
    /// Each entry stores the exact IMP that was active immediately before Klaviyo installed
    /// its callback on a concrete delegate class. Keeping entries per class allows wrapper or
    /// delegate replacement without silently leaving the new delegate uninstrumented.
    private final class State: @unchecked Sendable {
        private struct Entry {
            let priorIMP: IMP?
        }

        private let lock = NSLock()
        private var entries: [ObjectIdentifier: Entry] = [:]

        func claimInstallation(on hostClass: AnyClass, priorIMP: IMP?) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let identifier = ObjectIdentifier(hostClass)
            guard entries[identifier] == nil else { return false }
            entries[identifier] = Entry(priorIMP: priorIMP)
            return true
        }

        func removeInstallation(on hostClass: AnyClass) {
            lock.lock(); defer { lock.unlock() }
            entries.removeValue(forKey: ObjectIdentifier(hostClass))
        }

        func isInstalled(on hostClass: AnyClass) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return entries[ObjectIdentifier(hostClass)] != nil
        }

        func hasInstalledAncestor(of hostClass: AnyClass) -> Bool {
            lock.lock(); defer { lock.unlock() }
            var currentClass: AnyClass? = class_getSuperclass(hostClass)
            while let candidate = currentClass {
                if entries[ObjectIdentifier(candidate)] != nil {
                    return true
                }
                currentClass = class_getSuperclass(candidate)
            }
            return false
        }

        func hadPriorIMP(for identifier: ObjectIdentifier) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return entries[identifier]?.priorIMP != nil
        }

        func priorIMP(for hostClass: AnyClass) -> IMP? {
            lock.lock(); defer { lock.unlock() }
            var currentClass: AnyClass? = hostClass
            while let candidate = currentClass {
                if let entry = entries[ObjectIdentifier(candidate)] {
                    return entry.priorIMP
                }
                currentClass = class_getSuperclass(candidate)
            }
            return nil
        }

        #if DEBUG
        /// Resets logical swizzle state for test isolation.
        /// ObjC runtime method exchanges are permanent — callers must use a unique class per test.
        func reset() {
            lock.lock()
            entries = [:]
            lock.unlock()
        }
        #endif
    }

    private static let state = State()

    /// Installs token interception on the supplied delegate or the application's current
    /// effective delegate. The pre-main application setter hook calls this each time the
    /// delegate changes; `initialize(with:)` calls it again as an idempotent fallback.
    @MainActor
    static func swizzleIfPossible(on delegate: (any UIApplicationDelegate)?) {
        guard let delegate else { return }
        performSwizzle(on: resolveSwizzleTargetClass(for: delegate))
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

    /// Installs the donor IMP on `hostClass` while retaining the exact implementation that
    /// was active immediately beforehand. An inherited method is retained and the donor is
    /// grafted onto the subclass, leaving the superclass method table untouched.
    @MainActor
    private static func performSwizzle(on hostClass: AnyClass) {
        let originalSelector = #selector(
            UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        let donorSelector = #selector(
            KlaviyoAppDelegateSwizzler
                .klaviyo_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )

        guard let donorMethod = class_getInstanceMethod(
            KlaviyoAppDelegateSwizzler.self, donorSelector
        ) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.error(
                    "Swizzler donor method missing; device-token forwarding disabled."
                )
            }
            return
        }
        let donorIMP = method_getImplementation(donorMethod)
        let donorTypes = method_getTypeEncoding(donorMethod)
        let priorMethod = class_getInstanceMethod(hostClass, originalSelector)
        let resolvedPriorIMP = priorMethod.map(method_getImplementation)

        // If an already-instrumented superclass owns the reachable donor IMP, the subclass
        // is instrumented through inheritance. Recording the donor as the child's prior IMP
        // would make the donor forward to itself forever. Leave the child untouched so state
        // lookup walks to the ancestor and retrieves the real host implementation instead.
        if resolvedPriorIMP == donorIMP, state.hasInstalledAncestor(of: hostClass) {
            return
        }

        // Never record the donor IMP itself as a forwarding target — reachable if state and
        // the runtime's method table diverge (e.g. `_resetStateForTesting()`, or an ancestor
        // instrumented through a path with no tracked entry). Forwarding to the donor would
        // recurse into itself indefinitely.
        let priorIMP = resolvedPriorIMP == donorIMP ? nil : resolvedPriorIMP

        guard state.claimInstallation(on: hostClass, priorIMP: priorIMP) else { return }

        if classOwnsMethod(hostClass, selector: originalSelector),
           let hostMethod = class_getInstanceMethod(hostClass, originalSelector) {
            method_setImplementation(hostMethod, donorIMP)
            if #available(iOS 14.0, *) {
                Logger.notifications.info(
                    "Swizzled didRegisterForRemoteNotificationsWithDeviceToken on \(hostClass)."
                )
            }
        } else if class_addMethod(hostClass, originalSelector, donorIMP, donorTypes) {
            if #available(iOS 14.0, *) {
                let qualifier = priorIMP == nil ? "" : " inherited"
                Logger.notifications.info("Grafted\(qualifier) device-token callback onto \(hostClass).")
            }
        } else {
            state.removeInstallation(on: hostClass)
            if #available(iOS 14.0, *) {
                Logger.notifications.error("Unable to install device-token callback on \(hostClass).")
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
        state.hadPriorIMP(for: identifier)
    }

    static func _isInstalledForTesting(_ hostClass: AnyClass) -> Bool {
        state.isInstalled(on: hostClass)
    }

    static func _priorIMPForTesting(_ hostClass: AnyClass) -> IMP? {
        state.priorIMP(for: hostClass)
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
        KlaviyoSDK().setAutomatic(pushToken: deviceToken)

        let hostClass: AnyClass = type(of: self)
        guard let hostIMP = Self.state.priorIMP(for: hostClass) else { return }
        let originalSelector = #selector(
            UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        )
        typealias DeviceTokenIMP = @convention(c) (NSObject, Selector, UIApplication, NSData) -> Void
        let forwardIMP = unsafeBitCast(hostIMP, to: DeviceTokenIMP.self)
        forwardIMP(self, originalSelector, application, deviceToken as NSData)
    }
}
