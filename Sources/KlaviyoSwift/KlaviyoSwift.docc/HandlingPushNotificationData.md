# Handling Push Notification Data

Read the title, body, custom data and media from Klaviyo push notifications, and handle silent and
background pushes.

## Overview

Klaviyo sends three kinds of push notification. Each reaches your app through different delegate
methods:

| Type | Visible alert? | Wakes app in background? | Delegate method(s) |
|---|---|---|---|
| Standard push | Yes | No | `willPresent` (foreground) / `didReceive` (tapped) |
| Standard push + Background Processing | Yes | Yes | Same as above, **plus** `didReceiveRemoteNotification` |
| Silent push | No | Yes | `didReceiveRemoteNotification` only |

"Background Processing" is a toggle in the **Behaviors** tab of the Klaviyo push editor. It adds
`content-available: 1` to an otherwise normal, visible push, so your app also gets a background wake
alongside the alert. It isn't a silent push.

### Prerequisites

- The [Push Notifications capability](https://developer.apple.com/documentation/usernotifications/registering_your_app_with_apns#2980170)
  enabled in Xcode.
- **Background Modes > Remote notifications** enabled. Background Processing and silent push need it.
- For rich media only: a Notification Service Extension and a shared App Group. See
  [Setting Up a Notification Service Extension](/documentation/klaviyoswiftextension/notificationserviceextension).

## Read the title and body

Every visible push carries its title and body on `UNNotification`, so there's nothing to extract.
Implement the `UNUserNotificationCenterDelegate` methods described in
<doc:PushNotifications#Track-open-events>, and read `notification.request.content.title` and
`.body` in `willPresent`, or `response.notification.request.content.title` and `.body` in the tap
handler.

## Silent push notifications

Silent push notifications (also called background pushes) let your app receive payloads from
Klaviyo without showing a visible alert. They're typically used to trigger background work, such as
preparing content, personalizing the app interface or downloading new information from a server.

> Note: Silent push works by default. The SDK doesn't provide specific handling for silent push
> notifications. See Apple's guide to
> [enabling the remote notifications capability](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app#Enable-the-remote-notifications-capability)
> and [receiving background notifications](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app#Receive-background-notifications)
> for details.

To handle silent push notifications, implement the app delegate method yourself:

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    // Access custom key-value pairs from the top level
    if let customData = userInfo["key_value_pairs"] as? [String: String] {
        // Process your custom key-value pairs here
        for (key, value) in customData {
            print("Key: \(key), Value: \(value)")
        }
        completionHandler(.newData)
    } else {
        print("No key_value_pairs found in notification")
        completionHandler(.noData)
    }
}
```

> Important: **Always call `completionHandler`.** Skipping it risks iOS throttling future background
> wakes for your app. The method exists so that iOS can measure how efficiently you use the time it
> grants.

> Note: The iOS Simulator doesn't deliver silent push or Background Processing wakes, so this method
> never fires there. Test on a physical device.

## Background notifications (content-available)

Klaviyo can send a **standard** push (title, body and other visible notification UI) whose APNs
payload also includes **`content-available: 1`**. This is different from a silent push: a silent
push never shows an alert, while this is a normal, user-visible notification that *also* asks iOS to
wake your app in the background, so you can refresh data or run other work from the same
`userInfo`.

You still handle the visible notification through
[`UNUserNotificationCenterDelegate`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
when the message is presented or opened. The background wake for `content-available` uses the same
app delegate method as silent push,
`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`. Implement it as shown in
<doc:HandlingPushNotificationData#Silent-push-notifications>, and call `completionHandler` with
`.newData`, `.noData` or `.failed` when your background work finishes. Use the same Background
Modes > Remote notifications setup (see Apple's
[background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)
guide).

> Note: Background wakes are best-effort and may be throttled. As with silent push, test on a
> physical device, because the Simulator doesn't support the full remote-notification background
> path.

## Custom data

Klaviyo messages can include key-value pairs (custom data) on both standard and silent push
notifications. Read them from the `key_value_pairs` key of the notification's
[`userInfo`](https://developer.apple.com/documentation/foundation/nsnotification/1409222-userinfo)
dictionary:

- For silent pushes and background wakes, see the example in
  <doc:HandlingPushNotificationData#Silent-push-notifications>.
- For standard pushes, read the same key in your Notification Service Extension. See
  [Setting Up a Notification Service Extension](/documentation/klaviyoswiftextension/notificationserviceextension#Add-the-extension-code)
  and the example app's
  [`NotificationService.swift`](https://github.com/klaviyo/klaviyo-swift-sdk/blob/master/Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift).

This lets you pull extra information from the push payload and act on it, for example by triggering
background processing, logging analytics events or updating app content.

## Rich media (images and videos)

Rich media is handled automatically once the Notification Service Extension and App Group are in
place. You don't need extra code: Klaviyo's push payload carries the media, and the extension
downloads and attaches it before the notification is displayed. See
[Setting Up a Notification Service Extension](/documentation/klaviyoswiftextension/notificationserviceextension#Rich-push)
for setup and test payloads.
