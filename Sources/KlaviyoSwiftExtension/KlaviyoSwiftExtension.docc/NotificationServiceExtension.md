# Setting Up a Notification Service Extension

Add a Notification Service Extension so Klaviyo push notifications can show rich media, update the
badge count and display action buttons.

## Overview

A [Notification Service Extension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension)
ships as a separate bundle inside your iOS app. It runs before a push notification is displayed, so
`KlaviyoSwiftExtension` can download and attach media, set the badge count and register action
buttons. You need one if you intend to use rich push notifications, custom badge counts or custom
data. Push tokens, open tracking and the rest of the push setup live in `KlaviyoSwift`; see
[Push Notifications](/documentation/klaviyoswift/pushnotifications).

## Add the extension target

1. In Xcode, select **File > New > Target**.
2. Select the **Notification Service Extension** target from the **iOS > Application Extension**
   section.
3. Click **Next**.
4. Specify a name and other configuration details for your app extension.
5. Click **Finish**.

> Warning: The deployment target of your Notification Service Extension defaults to the latest iOS
> version. If this is later than your app's minimum supported iOS version, push notifications may
> not display attached media on older devices. To avoid this, set the extension's minimum
> deployment target to match your app's.

## Set up an App Group

Set up an App Group shared by your main app target and your Notification Service Extension:

1. Select your main app target > **Signing & Capabilities**.
2. Select **+ Capability** (make sure it's set to **All**, not Debug or Release) > **App Groups**.
3. Create a new App Group, following the recommended naming scheme
   `group.[MainTargetBundleId].[descriptor]`.
4. In your app's `Info.plist`, add a `klaviyo_app_group` entry as a String set to the App Group name.
5. Select your Notification Service Extension target > **Signing & Capabilities**.
6. Add an App Group with the same name as the main target's App Group.
7. In your Notification Service Extension's `Info.plist`, add a `klaviyo_app_group` entry as a String
   set to the App Group name.

## Install KlaviyoSwiftExtension

Add the `KlaviyoSwiftExtension` product to your Notification Service Extension target. With Swift
Package Manager, assign it to the extension target when you add the package. With CocoaPods, add
`pod 'KlaviyoSwiftExtension'` to the extension's target in your Podfile. See
[Getting Started](/documentation/klaviyoswift/gettingstarted#Install-the-SDK) for the full steps.

## Add the extension code

In your extension's `NotificationService.swift`, forward the two
`UNNotificationServiceExtension` callbacks to ``KlaviyoExtensionSDK``. This lets the SDK download
and attach media to the push notification and handle custom badge counts. The example below, taken
from the example app's
[`NotificationService.swift`](https://github.com/klaviyo/klaviyo-swift-sdk/blob/master/Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift),
also shows how to read custom data (key-value pairs) sent from Klaviyo.

```swift
import KlaviyoSwiftExtension
import UIKit
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var request: UNNotificationRequest!
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.request = request
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if let bestAttemptContent = bestAttemptContent {
            KlaviyoExtensionSDK.handleNotificationServiceDidReceivedRequest(
                request: self.request,
                bestAttemptContent: bestAttemptContent,
                contentHandler: contentHandler
            )
        }

        // Access key-value pairs
        let userInfo = request.content.userInfo
        if let kvPairs = userInfo["key_value_pairs"] as? [String: String] {
            for (key, value) in kvPairs {
                print("Key: \(key), Value: \(value)")
            }
        } else {
            print("No key_value_pairs found in notification")
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content,
        // otherwise the original push payload will be used.
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            KlaviyoExtensionSDK.handleNotificationServiceExtensionTimeWillExpireRequest(
                request: request,
                bestAttemptContent: bestAttemptContent,
                contentHandler: contentHandler
            )
        }
    }
}
```

## Rich push

> Note: Rich push notifications are supported in SDK version
> [2.2.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/2.2.0) and later.

[Rich push](https://help.klaviyo.com/hc/en-us/articles/16917302437275) adds images (png, jpg, gif)
and videos (mpeg, mp4) to push notifications. Once you've completed the steps above, your project
has a Notification Service Extension that calls into `KlaviyoSwiftExtension`, and rich media works
with no extra code: Klaviyo's push payload carries the media, and the extension downloads and
attaches it before the notification is displayed.

### Test rich push notifications

To test rich push notifications, you need three things:

- A push notification tester, such as Apple's
  [Push Notifications Console](https://developer.apple.com/notifications/push-notifications-console/)
  or a third-party tool such as
  [PushNotifications](https://github.com/onmyway133/PushNotifications).
- A push notification payload that resembles what Klaviyo would send. For example:

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

- A real device's push notification token. You can print it to the console from the
  `didRegisterForRemoteNotificationsWithDeviceToken` method in your app delegate.

With these three things, use the push notification tester to send a notification and make sure
everything is set up correctly.

## Badge count

Klaviyo can set or increment the badge count when you send a push notification. The extension
applies the badge count from the payload, using the App Group to share the current count with your
app. For autoclearing and for keeping the count in sync with other notification sources, see
[Push Notifications](/documentation/klaviyoswift/pushnotifications#Badge-count).

## Push action buttons

> Note: Push action buttons are supported in SDK version
> [5.3.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/5.3.0) and later.

Klaviyo supports adding
[custom push action buttons](https://help.klaviyo.com/hc/en-us/article/46285872166683) to push
notifications. Buttons show custom text and can deep link into or open your app when tapped. If a
button is tapped, the push open event includes the button's information. No additional setup is
needed beyond the extension code above. Klaviyo sends at most three action buttons per push; the
SDK registers whichever valid buttons the payload contains.

To test push action buttons, use Apple's
[Push Notifications Console](https://developer.apple.com/notifications/push-notifications-console/)
or a third-party tool such as [PushNotifications](https://github.com/onmyway133/PushNotifications),
and send a payload in this format to resemble what the SDK receives from Klaviyo:

```json
{
  "aps": {
    "alert": {
      "title": "New Arrivals Just for You",
      "body": "Check out our latest collection"
    },
    "mutable-content": 1,
    "sound": "default"
  },
  "body": {
    "_k": { },
    "action_buttons": [
      {
        "id": "someId",
        "label": "Go to Settings",
        "action": "deep_link",
        "url": "klaviyotest://settings"
      },
      {
        "id": "someOtherId",
        "label": "Open App",
        "action": "open_app"
      }
    ]
  }
}
```

To handle the deep links that action buttons open, see
[Deep Linking](/documentation/klaviyoswift/deeplinking).
