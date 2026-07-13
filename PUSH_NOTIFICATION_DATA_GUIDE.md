# Extracting Title, Body, Custom Data, and Media from Klaviyo Push Notifications (iOS)

This guide shows how to read the title, body, custom key-value pairs, and media (rich push) from a
push notification sent through Klaviyo, using the Klaviyo Swift SDK.

## Which push type are you handling?

| Type | Visible alert? | Wakes app in background? | Delegate method(s) |
|---|---|---|---|
| Standard push | Yes | No | `willPresent` (foreground) / `didReceive` (tapped) |
| Standard push + Background Processing | Yes | Yes | Same as above, **plus** `didReceiveRemoteNotification` |
| Silent push | No | Yes | `didReceiveRemoteNotification` only |

"Background Processing" is a toggle in the Klaviyo push editor's **Behaviors** tab. It adds
`content-available: 1` to an otherwise normal, visible push so your app also gets a background wake
alongside the alert — it is not a silent push.

## Prerequisites

- [Push Notifications capability](https://developer.apple.com/documentation/usernotifications/registering_your_app_with_apns#2980170) enabled in Xcode.
- Background Modes → **Remote notifications** enabled (needed for Background Processing and silent push).
- For rich media only: a Notification Service Extension + shared App Group. See
  [README § Installation](README.md#installation), step 2.

## 1. Title & body (any visible push)

Nothing to "extract" here — `UNNotification` already carries `title`/`body`. Implement the delegate:

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Called when the user taps the notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let handled = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: completionHandler)
        if !handled {
            completionHandler()
        }
    }

    // Called when a push arrives while the app is in the foreground
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
```

`title`/`body` are readable any time via `notification.request.content.title` / `.body`, or
`response.notification.request.content.title` / `.body` in the tap handler.

## 2. Custom data + background wake (Background Processing / silent push)

```swift
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

    completionHandler(.newData) // or .noData / .failed
}
```

> ⚠️ **Always call `completionHandler`.** Skipping it risks iOS throttling future background wakes to
> your app — this method exists specifically so iOS can measure how efficiently you use the time it grants.
>
> ⚠️ Test on a **physical device**. The Simulator does not deliver silent-push or Background-Processing
> wakes, so this method will never fire there.

## 3. Rich media (images & videos)

Handled automatically once the Notification Service Extension + App Group from Prerequisites are in
place — see the working reference implementation:
[`NotificationService.swift`](Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift).
No extra code is needed to trigger it; Klaviyo's push payload carries the media, and the extension
downloads and attaches it before the notification displays.

Test payloads (send via a real device token — printed from `didRegisterForRemoteNotificationsWithDeviceToken`):

**Image:**

```json
{
  "aps": {
    "alert": {
      "title": "Sample title for a Klaviyo push notification",
      "body": "Sample body for a Klaviyo push notification"
    },
    "mutable-content": 1
  },
  "rich-media": "https://picsum.photos/200/300.jpg",
  "rich-media-type": "jpg"
}
```

**Video:**

```json
{
  "aps": {
    "alert": {
      "title": "Video Push Notification",
      "body": "Check out this video content"
    },
    "mutable-content": 1
  },
  "rich-media": "https://example.com/videos/mp4/your_video.mp4",
  "rich-media-type": "mp4"
}
```

## Reference

Full documentation: [README § Push Notifications](README.md#push-notifications)
