//
//  AppDelegate.swift
//  SPMExampleAutomatic
//
// Automatic push integration — no token forwarding, no notification delegate code needed.
// The SDK handles all of that when `klaviyo_automatic_push_tracking` is set in Info.plist.
// For the manual integration reference (STEP1–STEP6) see Shared/AppDelegate.swift.
//

import KlaviyoForms
import KlaviyoLocation
import KlaviyoSwift
import SwiftUI
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: - Private members

    private var email: String? {
        UserDefaults.standard.object(forKey: "email") as? String
    }

    // MARK: App delegates

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Replace YOUR_PUBLIC_API_KEY with your actual Klaviyo public API key
        KlaviyoSDK()
            .initialize(with: "YOUR_PUBLIC_API_KEY")
            .registerForInAppForms()
            .registerGeofencing()
            .registerFormLifecycleHandler { event in
                switch event {
                case .formShown:
                    print("🎨 [Form Lifecycle] Form Shown: \(event.formId)")
                    print("   Form Name: \(event.formName)")
                case .formDismissed:
                    print("👋 [Form Lifecycle] Form Dismissed: \(event.formId)")
                    print("   Form Name: \(event.formName)")
                case let .formCtaClicked(_, _, buttonLabel, deepLinkUrl):
                    print("🖱️  [Form Lifecycle] Form CTA Clicked: \(event.formId)")
                    print("   Form Name: \(event.formName)")
                    print("   Button: \(buttonLabel) → \(deepLinkUrl)")
                }
            }

        KlaviyoSDK().create(event: .init(name: .customEvent("Opened kLM App")))

        if let email = email {
            KlaviyoSDK().set(email: email)
        }

        // Request push authorization — SDK proxy handles token forwarding and
        // notification response tracking automatically (no delegate code needed here)
        requestPushAuthorization()

        // Deep links from push notifications are routed through this handler by the SDK proxy
        KlaviyoSDK().registerDeepLinkHandler { [weak self] url in
            guard let self,
                  let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true),
                  let host = components.host,
                  let deeplink = DeepLinking(rawValue: host)
            else {
                print("Unhandled deep link: \(url)")
                return
            }
            handle(deeplink, with: url.absoluteString)
        }

        return true
    }

    // example of registering for forms to display on the applicationDidBecomeActive lifecycle event (every foreground event)
    func applicationDidBecomeActive(_ application: UIApplication) {
        KlaviyoSDK().registerForInAppForms()
    }

    // MARK: Push Notification implementation

    private func requestPushAuthorization() {
        // Register with APNs immediately so a device token is available regardless of
        // notification permission status. The SDK intercepts the token callback automatically.
        UIApplication.shared.registerForRemoteNotifications()

        let center = UNUserNotificationCenter.current()
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        center.requestAuthorization(options: options) { _, error in
            if let error = error {
                print("error = ", error)
            }
            // Call registerForRemoteNotifications again so Klaviyo always has the latest
            // push authorization status.
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        if error._code == 3010 {
            print("push notifications are not supported in the iOS simulator")
        } else {
            print("application:didFailToRegisterForRemoteNotificationsWithError: \(error)")
        }
    }

    // MARK: Silent Push Notification implementation

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let customData = userInfo["key_value_pairs"] as? [String: String] {
            for (key, value) in customData {
                print("Key: \(key), Value: \(value)")
            }
        } else {
            print("No key_value_pairs found in notification")
        }
        completionHandler(.noData)
    }

    // MARK: Deep linking implementation

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host
        else {
            print("Invalid deeplinking URL")
            return false
        }

        print("components: \(components.debugDescription)")

        guard let deeplink = DeepLinking(rawValue: host) else {
            print("Deeplink not found: \(host)")
            return false
        }

        handle(deeplink, with: url.description)

        return true
    }

    // MARK: private methods

    private func handle(_ deepLink: DeepLinking, with url: String) {
        switch deepLink {
        case .home:
            break
        case .menu:
            break
        case .checkout:
            break
        case .debug:
            let debugViewController = DebugViewController()
            debugViewController.debugMessage = url
            let navigation = UINavigationController(rootViewController: debugViewController)
            window?.rootViewController?.dismiss(animated: true)
            window?.rootViewController?.present(navigation, animated: true)
        }
    }
}
