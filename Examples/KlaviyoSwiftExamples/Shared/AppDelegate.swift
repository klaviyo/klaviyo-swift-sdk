//
//  AppDelegate.swift
//  KlaviyoSwift
//
//  Created by Katy Keuper on 10/05/2015.
//  Copyright (c) 2015 Katy Keuper. All rights reserved.
//

import KlaviyoForms
import KlaviyoLocation
// STEP1: Importing klaviyo SDK modules into your app code
// `KlaviyoSwift` is for analytics and push notifications and `KlaviyoForms` is for presenting marketing in app forms/messages
import KlaviyoSwift
import SwiftUI
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
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
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        // use the below options if you are interested in using provisional push notifications. Note that using this will not
        // show the push notifications prompt to the user.
        // let options: UNAuthorizationOptions = [.alert, .sound, .badge, provisional]
        center.requestAuthorization(options: options) { _, error in
            if let error = error {
                // Handle the error here.
                print("error = ", error)
            }

            // Enable or disable features based on the authorization status.
        }

        UIApplication.shared.registerForRemoteNotifications()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // STEP5: add the push device token to your Klaviyo user profile.
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

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // STEP7: [OPTIONAL] Build a "mobile inbox" from content-available pushes.
        //
        // When a push is sent with `content-available: 1`, iOS delivers it here in
        // your *app* process (whether the app is in the foreground or background).
        // That lets you persist the message locally and surface it later in an
        // in-app inbox — no Notification Service Extension and no App Group shared
        // container required. See `MobileInbox` below and `InboxView` for the UI.
        //
        // Heads up: content-available delivery is best-effort. iOS throttles
        // background pushes and will NOT wake an app the user has force-quit, so
        // some messages can be missed. If you must reliably capture every *visible*
        // notification, use a Notification Service Extension (`mutable-content`)
        // instead — see the NotificationServiceExtension target in this project.
        MobileInbox.shared.capture(from: userInfo)

        // Access custom key-value pairs from the top level
        if let customData = userInfo["key_value_pairs"] as? [String: String] {
            // Process your custom key-value pairs here
            for (key, value) in customData {
                print("Key: \(key), Value: \(value)")
            }
        } else {
            print("No key_value_pairs found in notification")
        }

        // Always call the completion handler so iOS knows you're done and keeps
        // delivering background pushes to your app.
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
        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner])
        } else {
            completionHandler([.alert])
        }
    }
}

// MARK: - Mobile Inbox (content-available example)

/// A single push captured for the in-app inbox.
struct InboxMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let receivedAt: Date
    /// Custom key/value data sent in the push (everything outside the `aps` dict).
    let data: [String: String]
    var isRead: Bool
}

/// A minimal "mobile inbox" backed by locally captured push notifications.
///
/// This demonstrates the **content-available** approach to an inbox: silent /
/// background pushes are delivered to
/// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` in your
/// app process, so you can persist them straight to local storage (here,
/// `UserDefaults`) and observe them from SwiftUI. No Notification Service
/// Extension and no App Group are involved.
///
/// Tradeoff to understand before shipping: `content-available` delivery is
/// **best-effort** — iOS throttles background pushes and will not wake a
/// force-quit app, so messages can be missed. When you need to reliably capture
/// every *visible* notification, intercept it in a Notification Service Extension
/// (`mutable-content`) instead. The two can be combined: NSE for reliable capture,
/// content-available to sync when the app is merely backgrounded.
final class MobileInbox: ObservableObject {
    static let shared = MobileInbox()

    @Published private(set) var messages: [InboxMessage]

    private let storageKey = "klaviyo_mobile_inbox"

    private init() {
        messages = Self.load(key: storageKey)
    }

    var unreadCount: Int { messages.lazy.filter { !$0.isRead }.count }

    /// Capture an incoming push payload into the inbox (newest first).
    ///
    /// A `content-available` push only carries a title/body when it is sent
    /// *alongside* an `alert`; a true silent push contains only custom data.
    func capture(from userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        var title = ""
        var body = ""
        switch aps?["alert"] {
        case let alert as [AnyHashable: Any]:
            title = alert["title"] as? String ?? ""
            body = alert["body"] as? String ?? ""
        case let alert as String:
            body = alert
        default:
            break
        }
        let data = userInfo.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String, key != "aps" else { return }
            result[key] = String(describing: pair.value)
        }

        guard !(title.isEmpty && body.isEmpty && data.isEmpty) else { return }
        let message = InboxMessage(id: UUID(), title: title, body: body, receivedAt: Date(), data: data, isRead: false)

        // App-delegate callbacks are delivered on the main thread, but marshal
        // explicitly so @Published mutations are always published on main.
        DispatchQueue.main.async {
            self.messages.insert(message, at: 0)
            self.persist()
        }
    }

    func markAsRead(_ message: InboxMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].isRead = true
        persist()
    }

    func clear() {
        messages = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func load(key: String) -> [InboxMessage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([InboxMessage].self, from: data) else {
            return []
        }
        return saved
    }
}
