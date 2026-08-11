import Foundation
import ObjectiveC.runtime
import OSLog
import UserNotifications

/// Hooks `UNUserNotificationCenter.setDelegate:` while preserving the exact setter IMP
/// installed immediately before Klaviyo. The hook captures each host assignment and then
/// restores the Klaviyo proxy as the effective delegate.
final class KlaviyoNotificationCenterDelegateSwizzler: NSObject, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        private struct Installation {
            let hostClass: AnyClass
            let priorIMP: IMP
        }

        private let lock = NSLock()
        private var installations: [ObjectIdentifier: Installation] = [:]

        func claimInstallation(on hostClass: AnyClass, priorIMP: IMP) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let identifier = ObjectIdentifier(hostClass)
            guard installations[identifier] == nil else { return false }
            installations[identifier] = Installation(hostClass: hostClass, priorIMP: priorIMP)
            return true
        }

        func priorIMP(for hostClass: AnyClass) -> IMP? {
            lock.lock(); defer { lock.unlock() }
            var currentClass: AnyClass? = hostClass
            while let candidate = currentClass {
                if let installation = installations[ObjectIdentifier(candidate)] {
                    return installation.priorIMP
                }
                currentClass = class_getSuperclass(candidate)
            }
            return nil
        }

        #if DEBUG
        func reset(setterSelector: Selector, installedIMP: IMP) {
            lock.lock()
            let installedHooks = Array(installations.values)
            installations = [:]
            lock.unlock()

            for hook in installedHooks {
                guard let setterMethod = class_getInstanceMethod(hook.hostClass, setterSelector),
                      method_getImplementation(setterMethod) == installedIMP else { continue }
                method_setImplementation(setterMethod, hook.priorIMP)
            }
        }
        #endif
    }

    private static let state = State()
    private static let setterSelector = #selector(setter: UNUserNotificationCenter.delegate)

    @MainActor
    static func installIfNeeded() {
        performInstall(on: UNUserNotificationCenter.self)
    }

    private static func performInstall(on hostClass: AnyClass) {
        let donorSelector = #selector(klaviyo_setDelegate(_:))
        guard let setterMethod = class_getInstanceMethod(hostClass, setterSelector),
              let donorMethod = class_getInstanceMethod(Self.self, donorSelector) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.error("Unable to install notification delegate setter hook.")
            }
            return
        }

        let priorIMP = method_getImplementation(setterMethod)
        let donorIMP = method_getImplementation(donorMethod)
        // Never record the donor IMP as the forwarding target; `klaviyo_setDelegate` would
        // call itself and recurse without bound if tracked state and the runtime method
        // table ever diverge.
        guard priorIMP != donorIMP else { return }
        guard state.claimInstallation(on: hostClass, priorIMP: priorIMP) else { return }
        method_setImplementation(setterMethod, donorIMP)
    }

    #if DEBUG
    static func _performInstallForTesting(on hostClass: AnyClass) {
        performInstall(on: hostClass)
    }

    static func _priorIMPForTesting(_ hostClass: AnyClass) -> IMP? {
        state.priorIMP(for: hostClass)
    }

    static func _resetStateForTesting() {
        let donorSelector = #selector(klaviyo_setDelegate(_:))
        guard let donorMethod = class_getInstanceMethod(Self.self, donorSelector) else { return }
        state.reset(
            setterSelector: setterSelector,
            installedIMP: method_getImplementation(donorMethod)
        )
    }
    #endif

    @objc
    private dynamic func klaviyo_setDelegate(
        _ assignedDelegate: (any UNUserNotificationCenterDelegate)?
    ) {
        let hostClass: AnyClass = type(of: self)
        guard let priorIMP = Self.state.priorIMP(for: hostClass) else { return }

        typealias DelegateSetterIMP = @convention(c) (NSObject, Selector, AnyObject?) -> Void
        let priorSetter = unsafeBitCast(priorIMP, to: DelegateSetterIMP.self)
        priorSetter(self, Self.setterSelector, assignedDelegate)

        // This method body is donated to `UNUserNotificationCenter.setDelegate:` via its
        // Objective-C IMP. At runtime `self` is therefore the notification center even though
        // Swift's static type remains the donor class. A normal conditional cast is optimized
        // as impossible in Release builds, so preserve the runtime receiver explicitly.
        let center = unsafeBitCast(self, to: UNUserNotificationCenter.self)
        let proxy = KlaviyoNotificationDelegate.shared
        let effectiveDelegate = center.delegate
        guard effectiveDelegate !== proxy else { return }

        proxy.captureHostDelegate(effectiveDelegate)
        priorSetter(self, Self.setterSelector, proxy)
    }
}
