import Foundation
import UIKit

@objc internal class PushNotificationSwizzler: NSObject {
    static let shared = PushNotificationSwizzler()
    private var isHandlingToken = false
    
    private override init() {
        super.init()
    }
    
    func start() {
        #if DEBUG
        print("[KlaviyoSDK] Starting push notification swizzling")
        #endif
        swizzleMethodsIfPossible()
    }
    
    private func swizzleMethodsIfPossible() {
        guard let appDelegate = UIApplication.shared.delegate else {
            #if DEBUG
            print("[KlaviyoSDK] Failed to swizzle: No app delegate found")
            #endif
            return
        }
        
        let appDelegateClass: AnyClass = type(of: appDelegate)
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(swizzled_application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        
        guard let originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector),
              let swizzledMethod = class_getInstanceMethod(PushNotificationSwizzler.self, swizzledSelector) else {
            #if DEBUG
            print("[KlaviyoSDK] Failed to swizzle: Could not find methods")
            #endif
            return
        }
        
        let didAddMethod = class_addMethod(
            appDelegateClass,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        
        if didAddMethod {
            class_replaceMethod(
                appDelegateClass,
                originalSelector,
                method_getImplementation(swizzledMethod),
                method_getTypeEncoding(swizzledMethod)
            )
            #if DEBUG
            print("[KlaviyoSDK] Successfully swizzled push notification method")
            #endif
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
            #if DEBUG
            print("[KlaviyoSDK] Successfully exchanged push notification method implementations")
            #endif
        }
    }
    
    @objc func swizzled_application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Prevent recursive calls
        guard !isHandlingToken else { return }
        isHandlingToken = true
        
        defer {
            isHandlingToken = false
        }
        
        #if DEBUG
        print("[KlaviyoSDK] Swizzled method called with token")
        #endif
        
        // Call original implementation if it exists
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let appDelegate = UIApplication.shared.delegate
        
        if let originalMethod = class_getInstanceMethod(type(of: appDelegate!), originalSelector) {
            typealias OriginalMethodType = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void
            let originalImplementation = unsafeBitCast(method_getImplementation(originalMethod), to: OriginalMethodType.self)
            originalImplementation(appDelegate!, originalSelector, application, deviceToken)
        }
        
        // Automatically set push token in KlaviyoSDK
        #if DEBUG
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[KlaviyoSDK] Setting push token: \(tokenString)")
        #endif
        
        KlaviyoSDK().set(pushToken: deviceToken)
    }
} 