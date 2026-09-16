import Foundation
import OSLog
import UIKit

/// Shared early/late installer invoked by the Objective-C application-delegate hook and
/// again from `initialize(with:)`. The two opt-in features remain fully independent.
@objc(KlaviyoAutomaticPushInstaller)
final class KlaviyoAutomaticPushInstaller: NSObject {
    @MainActor
    @objc(installForApplicationDelegate:)
    static func install(for applicationDelegate: (any UIApplicationDelegate)?) {
        if klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled() {
            klaviyoSwiftEnvironment.installNotificationDelegateHook()
            KlaviyoNotificationDelegate.shared.install(
                into: klaviyoSwiftEnvironment.notificationCenter()
            )
        } else if #available(iOS 14.0, *) {
            Logger.notifications.log("Automatic push tracking is off.")
        }

        if klaviyoSwiftEnvironment.isAutomaticPushTokenForwardingEnabled() {
            klaviyoSwiftEnvironment.installApplicationDelegateTokenHook(applicationDelegate)
        } else if #available(iOS 14.0, *) {
            Logger.notifications.log("Automatic token forwarding is off.")
        }
    }
}
