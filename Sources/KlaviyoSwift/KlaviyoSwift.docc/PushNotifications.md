# Push Notifications

Collect push tokens, request permission, and track push opens, either automatically or with your
own delegate code.

## Overview

To send push notifications to your users, the SDK registers each device's push token with Klaviyo
and tracks when users open a notification. You can let the SDK do this automatically (Option A), or
wire up the APNs and `UNUserNotificationCenterDelegate` callbacks yourself (Option B).

### Prerequisites

- An Apple developer [account](https://developer.apple.com/).
- [iOS push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971) configured in
  your Klaviyo account settings.
- The push notification capability enabled in your app. See <doc:GettingStarted>.

> Tip: **Which option should I use?**
>
> Choose **Option A** for a minimal-boilerplate integration. The SDK intercepts APNs callbacks and
> tracks push opens automatically, with no `UNUserNotificationCenterDelegate` code required.
>
> Choose **Option B** if you need direct control over `willPresent` behavior, are chaining multiple
> push notification SDKs and want to manage the delegate chain yourself, or have a hybrid flow that
> requires custom delegate logic.

## Option A: Automatic integration

The SDK can intercept APNs device-token callbacks and `UNUserNotificationCenter` delegate calls
automatically, so you don't need to implement `didRegisterForRemoteNotificationsWithDeviceToken` or
any `UNUserNotificationCenterDelegate` methods in your app delegate.

### Step 1: Enable automatic push behavior in Info.plist

Automatic push tracking and automatic device-token forwarding are two independent opt-in flags. For
the fully automatic, no-boilerplate integration, enable both:

```xml
<!-- Injects a notification-delegate proxy that tracks push opens automatically -->
<key>klaviyo_automatic_push_open_tracking</key>
<true/>
<!-- Forwards the APNs device token to Klaviyo automatically (no didRegister... code needed) -->
<key>klaviyo_automatic_push_token_forwarding</key>
<true/>
```

Each flag can be enabled on its own; enable only the behavior you want.

- If you enable push tracking without token forwarding, you must still collect the device token
  yourself and pass it to ``KlaviyoSDK/set(pushToken:)-(Data)`` (see
  <doc:PushNotifications#Collect-push-tokens>). Otherwise no token is registered with Klaviyo.
- If you enable token forwarding without push tracking, the device token is forwarded automatically,
  but you must track push opens yourself (see <doc:PushNotifications#Track-open-events>).

### Step 2: Initialize the SDK and request push authorization

```swift
import KlaviyoSwift
import UserNotifications

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
    registerForPushNotifications()
    return true
}

func registerForPushNotifications() {
    // Register with APNs immediately so a device token is available regardless of
    // notification permission status. The SDK intercepts the token callback automatically.
    UIApplication.shared.registerForRemoteNotifications()

    let center = UNUserNotificationCenter.current()
    let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    // To use provisional push notifications (no user prompt), use:
    // let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]
    center.requestAuthorization(options: options) { _, error in
        if let error = error {
            print("Push authorization error: \(error)")
        }
        // Irrespective of the authorization status call `registerForRemoteNotifications` here so that
        // the `didRegisterForRemoteNotificationsWithDeviceToken` delegate is called. Doing this
        // will make sure that Klaviyo always has the latest push authorization status.
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
```

> Note: Silent push (`content-available`) isn't intercepted automatically. If you use silent or
> background pushes, implement `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
> in your app delegate. See <doc:HandlingPushNotificationData>.

### Foreground presentation

With `klaviyo_automatic_push_open_tracking` enabled and no `UNUserNotificationCenterDelegate` of
your own, the SDK shows a visible foreground banner by default (`[.list, .banner, .badge, .sound]`
on iOS 14 and later, `[.alert, .badge, .sound]` on iOS 13). You don't need to implement
`willPresent` just to get a banner in the foreground.

For a runnable reference, see the
[SPMExampleAutomatic](https://github.com/klaviyo/klaviyo-swift-sdk/tree/master/Examples/KlaviyoSwiftExamples/SPMExample/SPMExampleAutomatic)
target.

Once your first push notifications are sent and opened, you should start to see _Opened Push_
metrics in your Klaviyo dashboard.

## Option B: Manual integration

Use this path when you need explicit control over the notification delegate chain: for example, to
customize `willPresent` behavior, chain multiple notification SDKs manually, or integrate with a
hybrid notification flow.

### Collect push tokens

To send push notifications to your users, collect their push tokens and register them with Klaviyo
by calling ``KlaviyoSDK/set(pushToken:)-(Data)``. It registers the push token and the current
authorization state through the
[Create Client Push Token API](https://developers.klaviyo.com/en/reference/create_client_push_token).

- Call
  [`registerForRemoteNotifications()`](https://developer.apple.com/documentation/uikit/uiapplication/1623078-registerforremotenotifications)
  to request a push token from APNs. This is typically done in the
  [`application(_:didFinishLaunchingWithOptions:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622921-application)
  method of your app delegate.
- Implement the delegate method
  [`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:didregisterforremotenotificationswithdevicetoken:))
  in your app delegate to receive the push token from APNs and register it with Klaviyo.

### Request push notification permission

You can request permission anywhere in your app where it makes sense to prompt users. Apple
provides [guidelines](https://developer.apple.com/documentation/usernotifications/asking_permission_to_use_notifications)
on when and how to ask. The following example requests permission in
`application(_:didFinishLaunchingWithOptions:)` in the app delegate. This may not be the ideal
place, because it can interrupt the app's startup experience.

After you set a push token, the SDK automatically tracks changes to the user's notification
permission whenever the app is opened or resumed from the background.

```swift
import KlaviyoSwift
import UserNotifications

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
    registerForPushNotifications()
    return true
}

func registerForPushNotifications() {
    // Register with APNs immediately so a device token is available regardless of
    // notification permission status. The token is forwarded to Klaviyo via
    // didRegisterForRemoteNotificationsWithDeviceToken below.
    UIApplication.shared.registerForRemoteNotifications()

    let center = UNUserNotificationCenter.current()
    center.delegate = self
    let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    // To use provisional push notifications (no user prompt), use:
    // let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]
    center.requestAuthorization(options: options) { _, error in
        if let error = error {
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

func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    KlaviyoSDK().set(pushToken: deviceToken)
}
```

### Track open events

When a user taps a push notification, the system calls your delegate's
[`userNotificationCenter(_:didReceive:withCompletionHandler:)`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/1649501-usernotificationcenter).
When a notification arrives while the app is in the foreground, it calls
[`userNotificationCenter(_:willPresent:withCompletionHandler:)`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/1649518-usernotificationcenter).
Implement both in your app delegate, and pass the response to
``KlaviyoSDK/handle(notificationResponse:withCompletionHandler:)`` to record the open:

```swift
// Set the UNUserNotificationCenterDelegate to self in didFinishLaunchingWithOptions
// (see "Request push notification permission" above).
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Called when the user interacts with the push notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        // If this notification is Klaviyo's notification we'll handle it,
        // else pass it on to the next push notification service to which it may belong
        let handled = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: completionHandler)
        if !handled {
            completionHandler()
        }
    }

    // Called when the app receives a push notification while in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner])
        } else {
            completionHandler([.alert])
        }
    }
}
```

> Note: To make sure push notifications that contain deep links (a custom URL scheme or a universal
> link) are handled properly, see <doc:DeepLinking>.

Once your first push notifications are sent and opened, you should start to see _Opened Push_
metrics in your Klaviyo dashboard.

For runnable reference examples, see
[SPMExample](https://github.com/klaviyo/klaviyo-swift-sdk/tree/master/Examples/KlaviyoSwiftExamples/SPMExample)
or
[CocoapodsExample](https://github.com/klaviyo/klaviyo-swift-sdk/tree/master/Examples/KlaviyoSwiftExamples/CocoapodsExample).

## Badge count

> Note: Setting or incrementing the badge count is available in SDK version
> [4.1.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/4.1.0) and later.

Klaviyo supports setting or incrementing the badge count when you send a push notification. For this
to work, you must set up the Notification Service Extension and an App Group, as described in
[Setting Up a Notification Service Extension](/documentation/klaviyoswiftextension/notificationserviceextension).

### Autoclearing

By default, the SDK clears the badge count when the app opens. To turn this off, add a
`klaviyo_badge_autoclearing` entry to your app's `Info.plist` as a Boolean set to `NO`. Set it back
to `YES` to turn automatic clearing on again.

### Handling other badging sources

The SDK handles the badge count for Klaviyo pushes automatically. If you need to update the badge
count to account for other notification sources, call ``KlaviyoSDK/setBadgeCount(_:)``. It updates
the badge count and keeps it in sync with the SDK. Use it instead of (not in addition to) setting the
badge count with `UNUserNotificationCenter` or `UIApplication` methods.

## Push action buttons

> Note: Push action buttons are supported in SDK version
> [5.3.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/5.3.0) and later.

Klaviyo can add [custom push action buttons](https://help.klaviyo.com/hc/en-us/article/46285872166683)
to push notifications. The `KlaviyoSwiftExtension` in your Notification Service Extension registers
the buttons, and push opens from a button tap are tracked like any other open. See
[Setting Up a Notification Service Extension](/documentation/klaviyoswiftextension/notificationserviceextension#Push-action-buttons)
for details and a test payload.

## See also

- <doc:HandlingPushNotificationData>: read custom data and handle silent and background pushes.
- <doc:DeepLinking>: route users from a notification to the right screen.
- <doc:AdvancedTopics>: Sandbox push environments, logging and retries.
