//
//  AppDelegate.swift
//  KlaviyoSwift
//
//  Created by Katy Keuper on 10/05/2015.
//  Copyright (c) 2015 Katy Keuper. All rights reserved.
//
// Manual push integration reference (STEP1–STEP6).
// For the automatic push integration example (no push code in AppDelegate),
// see SPMExampleAutomatic/AppDelegate.swift.
//

import KlaviyoForms
import KlaviyoLocation
// STEP1: Importing klaviyo SDK modules into your app code
// `KlaviyoSwift` is for analytics and push notifications and `KlaviyoForms` is for presenting marketing in app forms/messages
import KlaviyoSwift
import SwiftUI
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    // STEP2D: [OPTIONAL] To demo list subscriptions, set a list ID from your account.
    // Leave `nil` to hide the Subscribe button entirely.
    static let subscriptionListId: String? = nil

    // MARK: - Private members

    private var email: String? {
        UserDefaults.standard.object(forKey: "email") as? String
    }

    private var zip: String? {
        UserDefaults.standard.object(forKey: "zip") as? String
    }

    // MARK: App delegates

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // STEP2: Setup Klaviyo SDK with api key
        KlaviyoSDK()
            .initialize(with: "YOUR_PUBLIC_API_KEY")
            .registerForInAppForms() // STEP2A: register for in app forms
            .registerGeofencing() // STEP2B: register for in geofencing
            .registerFormLifecycleHandler { event in
                // STEP2C: [OPTIONAL] Register for form lifecycle events to track form interactions
                // This handler is called whenever a form is shown, dismissed, or a CTA is clicked

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

        // EXAMPLE: of how to track an event
        KlaviyoSDK().create(event: .init(name: .customEvent("Opened kLM App")))

        // STEP3: register the user email with klaviyo so there is an unique way to identify your app user.
        if let email = email {
            KlaviyoSDK().set(email: email)
        }

        // STEP4: Setting up push notifcations
        howToSetupPushNotifications()

        return true
    }

    // example of registering for forms to display on the applicationDidBecomeActive lifecycle event (every foreground event)
    func applicationDidBecomeActive(_ application: UIApplication) {
        KlaviyoSDK().registerForInAppForms()
    }

    // MARK: Push Notification implementation

    private func howToSetupPushNotifications() {
        // Register with APNs immediately so a device token is available regardless of
        // notification permission status.
        UIApplication.shared.registerForRemoteNotifications()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        // use the below options if you are interested in using provisional push notifications. Note that using this will not
        // show the push notifications prompt to the user.
        // let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]
        center.requestAuthorization(options: options) { _, error in
            if let error = error {
                // Handle the error here.
                print("error = ", error)
            }

            // Irrespective of the authorization status call `registerForRemoteNotifications` here so that
            // the `didRegisterForRemoteNotificationsWithDeviceToken` delegate is called. Doing this
            // will make sure that Klaviyo always has the latest push authorization status.
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // STEP5: add the push device token to your Klaviyo user profile.

        #if DEBUG
        // Print the token as a hex string for debugging. The token is a device identifier, so
        // this is intentionally Debug-only and never runs in a Release build.
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📱 APNs device token: \(tokenString)")
        #endif

        KlaviyoSDK().set(pushToken: deviceToken)
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

    // This fires for both silent pushes and "Background Processing" pushes (content-available: 1,
    // enabled from the Behaviors tab of a Klaviyo push message) whether the app is foregrounded,
    // backgrounded, or terminated by the system. Background wakes are best-effort and only
    // testable on a physical device — the Simulator does not deliver them.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Access custom key-value pairs from the top level
        let customData = PushPayload.customData(from: userInfo)
        #if DEBUG
        if customData.isEmpty {
            print("No key_value_pairs found in notification")
        } else {
            // Process your custom key-value pairs here
            for (pairKey, value) in customData {
                print("Key: \(pairKey), Value: \(value)")
            }
        }
        #endif

        // A visible alert delivered while the app is active also triggers `willPresent`, which
        // already logs it — skip here to avoid a duplicate entry. Silent pushes (no alert) never
        // trigger `willPresent`, so they must always be logged from this method regardless of
        // app state.
        let hasVisibleAlert = PushPayload.hasVisibleAlert(userInfo)
        guard hasVisibleAlert, application.applicationState == .active else {
            let (title, body) = PushPayload.alertTitleAndBody(from: userInfo)
            // Only call the completion handler once the entry is actually persisted — the app
            // could be suspended immediately after fetchCompletionHandler runs, and the store's
            // write happens on an async main-queue hop.
            PushLogStore.shared.record(source: .background, title: title, body: body, customData: customData) {
                completionHandler(.newData)
            }
            return
        }

        // Do your background work here (refresh data, etc.), then always call the completion
        // handler so iOS can measure your app's background efficiency.
        completionHandler(.newData)
    }

    // MARK: Deep linking implementation

    // If you would like to support deep links the following delegate needs to be implemented
    // it's upto the developer to decide what to do with the URL in this method.
    // NOTE that for custom URI schemes if you have a path that is deeper than 1, part of it will be the host and
    // part of it will be in path so please be careful to parse the deep link fully.
    // Ex: klaviyo://path1/path2 would be host = path1 and path = path2
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

        // Create the deep link
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
            // this is where we could present the home view
            break
        case .menu:
            // this is where we could present the menu view
            break
        case .checkout:
            // this is where we could present the checkout view
            break
        case .debug:
            // sending debug should show the deeplink URL in code
            let debugViewController = DebugViewController()
            debugViewController.debugMessage = url
            let navigation = UINavigationController(rootViewController: debugViewController)
            window?.rootViewController?.dismiss(animated: true)
            window?.rootViewController?.present(navigation, animated: true)
        }
    }
}

// MARK: App delegate extensions

// STEP6: Add this extension on AppDelegate for additional push notifications handling
extension AppDelegate: UNUserNotificationCenterDelegate {
    // below method will be called when the user interacts with the push notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        PushLogStore.shared.record(
            source: .tapped,
            title: content.title,
            body: content.body,
            customData: PushPayload.customData(from: content.userInfo)
        )

        // If this notifiation is Klaviyo's notification we'll handle it
        // else pass it on to the next push notification service to which it may belong
        let handled = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: completionHandler)
        if !handled {
            completionHandler()
        }
    }

    // below method is called when the app receives push notifications when the app is the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Extract the visible title/body from a standard (non-silent) push
        let title = notification.request.content.title
        let body = notification.request.content.body
        #if DEBUG
        print("📬 [Foreground Push] Title: \(title), Body: \(body)")
        #endif

        PushLogStore.shared.record(
            source: .foreground,
            title: title,
            body: body,
            customData: PushPayload.customData(from: notification.request.content.userInfo)
        )

        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner])
        } else {
            completionHandler([.alert])
        }
    }
}
