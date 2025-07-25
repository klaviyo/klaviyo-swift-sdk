# klaviyo-swift-sdk

![CI status](https://github.com/klaviyo/klaviyo-swift-sdk/actions/workflows/swift.yml/badge.svg)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)
![SPM version](https://img.shields.io/github/v/release/klaviyo/klaviyo-swift-sdk)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
![Minimum deployment version](https://img.shields.io/badge/minimum_iOS_deployment_target-iOS13-brightgreen)

## Contents
- [Overview](#overview)
- [Installation](#installation)
- [Initialization](#initialization)
- [Profile Identification](#profile-identification)
  - [Reset Profile](#reset-profile)
  - [Anonymous Tracking Notice](#anonymous-tracking-notice)
- [Event tracking](#event-tracking)
- [Push Notifications](#push-notifications)
  - [Prerequisites](#prerequisites)
  - [Collecting Push Tokens](#collecting-push-tokens)
  - [Request Push Notification Permission](#request-push-notification-permission)
  - [Receiving Push Notifications](#receiving-push-notifications)
    - [Tracking Open Events](#tracking-open-events)
    - [Deep Linking](#deep-linking)
      - [Option 1: URL Schemes](#option-1-url-schemes)
      - [Option 2: Universal Links](#option-2-universal-links)
    - [Rich Push](#rich-push)
    - [Badge Count](#badge-count)
       - [Autoclearing](#autoclearing)
      - [Handling Other Badging Sources](#handling-other-badging-sources)
    - [Silent Push Notifications](#silent-push-notifications)
    - [Custom Data](#custom-data)
- [In-App Forms](#in-app-forms)
  - [Prerequisites](#prerequisites)
  - [Setup](#setup)
    - [In-App Forms Session Configuration](#in-app-forms-session-configuration)
  - [Unregistering from In-App Forms](#unregistering-from-in-app-forms)
  - [Deep linking](#deep-linking-1)
- [Additional Details](#additional-details)
  - [Sandbox Support](#sandbox-support)
  - [SDK Data Transfer](#sdk-data-transfer)
  - [Retries](#retries)
  - [License](#license)

## Overview

The Klaviyo Swift SDK allows developers to incorporate Klaviyo's analytics and push notification functionality into their iOS applications.
The SDK assists in identifying users and tracking events via [Klaviyo Client APIs](https://developers.klaviyo.com/en/reference/api_overview).
To reduce performance overhead, API requests are queued and sent in batches.
The queue is persisted to local storage so that data is not lost if the device is offline or the app is terminated.

Once integrated, your marketing team will be able to better understand your app users' needs and send them timely messages via APNs.

## Installation

1. Enable push notification capabilities in your Xcode project. The section "Enable the push notification capability" in this [Apple developer guide](https://developer.apple.com/documentation/usernotifications/registering_your_app_with_apns#2980170) provides detailed instructions.
2. If you intend to use [rich push notifications](#rich-push), [custom badge counts](#custom-badge-count), or [custom data](#custom-data), add a [Notification Service Extension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension) to your Xcode project. A Notification Service Extension ships as a separate bundle inside your iOS app. To add this extension to your app:
   - Select File > New > Target in Xcode.
   - Select the Notification Service Extension target from the iOS > Application extension section.
   - Click Next.
   - Specify a name and other configuration details for your app extension.
   - Click Finish.

    > ⚠️ The deployment target of your notification service extension defaults to the latest iOS version.
             If this exceeds your app's minimum supported iOS version, push notifications may not display attached media on older devices.
             To avoid this, ensure the extension's minimum deployment target matches that of your app. ⚠️

    Set up an App Group between your main app target and your Notification Service Extension.
    - Select your main app target > Signing & Capabilities
    - Select + Capability (make sure it is set to All not Debug or Release) > App Groups
    - Create a new App Group based on the recommended naming scheme `group.[MainTargetBundleId].[descriptor]`
    - In your app's `Info.plist`, add a new entry for `klaviyo_app_group` as a String with the App Group name
    - Select your Notification Service Extension target > Signing & Capabilities
    - Add an App Group with the same name as the main target's App Group
    - In your Notification Service Extension's `Info.plist`, add a new entry for `klaviyo_app_group` as a String with the App Group name

3. Based on which dependency manager you use, follow the instructions below to install the Klaviyo's dependencies.

      <details>
      <summary>Swift Package Manager [Recommended]</summary>

      KlaviyoSwift and KlaviyoForms are available via [Swift Package Manager](https://swift.org/package-manager). Follow the steps below to install.

      1. Open your project and navigate to your project’s settings.
      2. Select the **Package Dependencies** tab and click on the **add** button below the packages list.
      3. Enter the URL of the Swift SDK repository `https://github.com/klaviyo/klaviyo-swift-sdk` in the text field. This should bring up the package on the screen.
      4. For the dependency rule dropdown select - **Up to Next Major Version** and leave the pre-filled versions as is.
      5. Click **Add Package**.
      6. On the next prompt, assign the package product `KlaviyoSwift` and `KlaviyoForms` to your app target and `KlaviyoSwiftExtension` to the notification service extension target (if one was created) and click **Add Package**.

      </details>

      <details>
      <summary>CocoaPods</summary>

      KlaviyoSwift is available through [CocoaPods](https://cocoapods.org/pods/KlaviyoSwift).

      1. To install, add the following lines to your Podfile. Be sure to replace `YourAppTarget` and `YourAppNotificationServiceExtenionTarget` with the names of your app and notification service extension targets respectively.

      ```ruby
      target 'YourAppTarget' do
        pod 'KlaviyoSwift'
      end

      target 'YourAppTarget' do
        pod 'KlaviyoForms'
      end

      target 'YourAppNotificationServiceExtenionTarget' do
        pod 'KlaviyoSwiftExtension'
      end
      ```
      2. Run `pod install` to complete the integration.
      The library can be kept up-to-date via `pod update KlaviyoSwift` and `pod update KlaviyoSwiftExtension`.
      </details>

4. Finally, in the `NotificationService.swift` file add the code for the two required delegates from [this](Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift) file.
  This sample covers calling into Klaviyo so that we can download and attach the media to the push notification as well as handle custom badge counts. It also demonstrates how to access custom data (key-value pairs) sent from Klaviyo.

> Advanced: If you are using multiple push sending providers, to distinguish a message from Klaviyo you can check for the presence of the `_k` parameter within the message's payload body. For reference, check out the implementation of `KlaviyoSDK().handle()`.

## Initialization
The SDK must be initialized with the short alphanumeric [public API key](https://help.klaviyo.com/hc/en-us/articles/115005062267#difference-between-public-and-private-api-keys1)
for your Klaviyo account, also known as your Site ID.

```swift
// AppDelegate

import KlaviyoSwift

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
        return true
    }
}
```

The SDK **should** be initialized before any other Klaviyo SDK methods are called.

## Profile Identification
The SDK provides methods to identify your users as Klaviyo profiles via the [Create Client Profile API](https://developers.klaviyo.com/en/reference/create_client_profile).
A profile can be identified by any combination of the following:

* External ID: A unique identifier used by customers to associate Klaviyo profiles with profiles in an external system, such as a point-of-sale system. Format varies based on the external system.
* Individual's email address
* Individual's phone number in [E.164 format](https://help.klaviyo.com/hc/en-us/articles/360046055671#h_01HE5ZYJEAHZKY6WZW7BAD36BG)

These above identifiers are persisted to local storage so that the SDK can keep track of the current user/profile for you when you make event requests or want to set a push token etc.

Profile identifiers can be set all at once or individually. Either way, the SDK will group and batch API calls to improve performance.

The following code demonstrates how to set profile identifiers:

```swift
// organization, title, image, location and additional properties (dictionary) can also be set using the below constructor
let profile = Profile(email: "junior@blob.com",  firstName: "Blob",  lastName: "Jr.")
KlaviyoSDK().set(profile: profile)

// or setting individual properties
KlaviyoSDK().set(profileAttribute: .firstName, value: "Blob")
KlaviyoSDK().set(profileAttribute: .lastName, value: "Jr.")
```

### Reset Profile
To start a new profile altogether (e.g. if a user logs out) either call `KlaviyoSDK().resetProfile()` to clear the currently tracked profile identifiers,
or use `KlaviyoSDK().set(profile: profile)` to overwrite it with a new profile object.

```swift
// start a profile for Blob Jr.
let profile = Profile(email: "junior@blob.com",  firstName: "Blob",  lastName: "Jr.")
KlaviyoSDK().set(profile: profile)

// stop tracking Blob Jr.
KlaviyoSDK().resetProfile()

// start a profile for Robin Hood
let profile = Profile(email: "robin@hood.com",  firstName: "Robin",  lastName: "Hood")
KlaviyoSDK().set(profile: profile)
```
### Anonymous Tracking Notice

Klaviyo will track unidentified users with an autogenerated ID whenever a push token is set or an event is created.
That way, you can collect push tokens and track events prior to collecting profile identifiers such as email or phone number.
When an identifier is provided, Klaviyo will merge the anonymous user with an identified user.

## Event tracking

The SDK provides tools for tracking events that users perform on your app via the [Create Client Event API](https://developers.klaviyo.com/en/reference/create_client_event).
Below is an example of how to track an event:

```swift
// using a predefined event name
let event = Event(name: .StartedCheckoutMetric,
                  properties: [
                        "name": "cool t-shirt",
                        "color": "blue",
                        "size": "medium",
                      ],
                  value: 166 )

KlaviyoSDK().create(event: event)

// using a custom event name
let customEvent = Event(name: .CustomEvent("Checkout Completed"),
                  properties: [
                        "name": "cool t-shirt",
                        "color": "blue",
                        "size": "medium",
                      ],
                  value: 166)

KlaviyoSDK().create(event: customEvent)
```

### Arguments

The `create` method takes an event object as an argument. The event can be constructed with the following arguments:
- [required] `name`: The name of the event you want to track, as a `EventName` enum. A list of common Klaviyo defined event metrics can be found in `Event.EventName`. You can also create custom events by using the `CustomEvent` enum case of `Event.EventName`
- `properties`: A dictionary of properties that are specific to the event. This argument is optional.
- `value`: A numeric value (`Double`) to associate with this event. For example, the dollar amount of a purchase.

## Push Notifications

### Prerequisites

* An apple developer [account](https://developer.apple.com/).
* Configure [iOS push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971) in Klaviyo account settings.

### Collecting Push Tokens

In order to send push notifications to your users, you must collect their push tokens and register them with Klaviyo.
This is done via the `KlaviyoSDK().set(pushToken:)` method, which registers a push token and current authorization state
via the [Create Client Push Token API](https://developers.klaviyo.com/en/reference/create_client_push_token).

* Call [`registerForRemoteNotifications()`](https://developer.apple.com/documentation/uikit/uiapplication/1623078-registerforremotenotifications)
to request a push token from APNs. This is typically done in the [`application:didFinishLaunchingWithOptions:`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622921-application) method of your app delegate.
* Implement the delegate method [`application:didRegisterForRemoteNotificationsWithDeviceToken`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/1428766-application)
in your application delegate to receive the push token from APNs and register it with Klaviyo.

Below is the code to do both of the above steps:
```swift
import KlaviyoSwift

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")

    UIApplication.shared.registerForRemoteNotifications()

    return true
}

func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    KlaviyoSDK().set(pushToken: deviceToken)
}
```

### Request Push Notification Permission

Once the push token is obtained, the next step is to request permission from your users to send them push notifications.
You can add the permission request code anywhere in your application where it makes sense to prompt users for this permission.
Apple provides some [guidelines](https://developer.apple.com/documentation/usernotifications/asking_permission_to_use_notifications)
on the best practices for when and how to ask for this permission. The following example demonstrates how to request push permissions
within the [`application:didFinishLaunchingWithOptions:`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622921-application)
method in the application delegate file. However, it's worth noting that this may not be the ideal location as it could interrupt the app's startup experience.

After setting a push token, the Klaviyo SDK will automatically track changes to
the user's notification permission whenever the application is opened or resumed from the background.

Below is example code to request push notification permission:
```swift
import UserNotifications

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")

    UIApplication.shared.registerForRemoteNotifications()

    let center = UNUserNotificationCenter.current()
    center.delegate = self as? UNUserNotificationCenterDelegate // the type casting can be removed once the delegate has been implemented
    let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    // use the below options if you are interested in using provisional push notifications. Note that using this will not
    // show the push notifications prompt to the user.
    // let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]
    center.requestAuthorization(options: options) { granted, error in
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

    return true
}
```

### Receiving Push Notifications

#### Tracking Open Events

When a user taps on a push notification, Implement  [`userNotificationCenter:didReceive:withCompletionHandler`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/1649501-usernotificationcenter)
and [`userNotificationCenter:willPresent:withCompletionHandler`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/1649518-usernotificationcenter) in your application delegate to handle receiving push notifications
when the app is in the background and foreground respectively.

Below is an example of how to handle push notifications in your app delegate:
```swift
// be sure to set the UNUserNotificationCenterDelegate to self in the didFinishLaunchingWithOptions method (refer the requesting push notification permission section above for more details on this)
extension AppDelegate: UNUserNotificationCenterDelegate {
    // below method will be called when the user interacts with the push notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        // If this notification is Klaviyo's notification we'll handle it
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
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner])
        } else {
            completionHandler([.alert])
        }
    }
}
```

Once your first push notifications are sent and opened, you should start to see _Opened Push_ metrics within your Klaviyo dashboard.

#### Deep Linking

>  ℹ️  Your app needs to use version 1.7.2 at a minimum in order for the below steps to work.

[Deep Links](https://help.klaviyo.com/hc/en-us/articles/14750403974043) allow you to navigate to a particular page within your app in response to the user opening a push notification.

You need to configure deep links in your app for them to work. The configuration process for Klaviyo is no different from what is required for handling deep linking in general,
so you can follow the [Apple documentation](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app) for deep linking in conjunction
with the steps outlined here.

You have two options for implementing deep links: URL schemes and Universal Links.

##### Option 1: URL Schemes

URL schemes are the traditional and simpler way of deep linking from a push notification to your app.
However, these links will only work if your mobile app is installed on a device and will not be understood by
a web browser if, for example, you want to link from an email to your app.

###### Step 1: Register the URL scheme

In order for Apple to route a deep link to your application you need to register a URL scheme in your application's Info.plist file. This can be done using the editor that xcode provides from the Info tab of your project settings or by editing the Info.plist directly.

The required fields are as following:

1. **Identifier** - The identifier you supply with your scheme distinguishes your app from others that declare support for the same scheme. To ensure uniqueness, specify a reverse DNS string that incorporates your company’s domain and app name. Although using a reverse DNS string is a best practice, it doesn’t prevent other apps from registering the same scheme and handling the associated links.
1. **URL schemes** - In the URL Schemes box, specify the prefix you use for your URLs.
1. **Role** - Since your app will be editing the role select the role as editor.

In order to edit the Info.plist directly, just fill in your app specific details and paste this in your plist.

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>{your_unique_identifier}</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>{your_URL_scheme}</string>
        </array>
    </dict>
</array>
```

###### Step 2: Whitelist supported URL schemes

Since iOS 9 Apple has mandated that the URL schemes that your app can open need to also be listed in the Info.plist. This is in addition to Step 1 above. Even if your app isn't opening any other apps, you still need to list your app's URL scheme in order for deep linking to work.

This needs to be done in the Info.plist directly:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>{your custom URL scheme}</string>
</array>
```

###### Step 3: Implement handling deep links in your app

Steps 1 and 2 enable your app to receive deep links, but you also need to handle these links within your app.
This is done by implementing the [`application:openURL:options:`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application)
method in your app delegate.

Example:

```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
) -> Bool {
    guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true)
    else {
       print("Invalid deep linking URL")
       return false
    }

    print("components: \(components.debugDescription)")

    return true
}
```

If you are using SwiftUI, then you can implement [`onOpenURL(perform:)`](<https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)>) as a view modifier in the view you intent to handle deep links. This may or may not be the root of your scene.

Example:

```swift
@main
struct MyApplication: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .onOpenURL { url in
          // handle the URL that must be opened
        }
    }
  }
}
```

Finally, we have an example app (`Examples/KlaviyoSwiftExamples`) in the SDK repo that you can reference to get an example of how to implement deep links in your app.

Once the above steps are complete, you can send push notifications from the Klaviyo Push editor within the Klaviyo website.
Here you can build and send a push notification through Klaviyo to make sure that the URL shows up in the handler you implemented in Step 3.

Additionally, you can also locally trigger a deep link to make sure your code is working using the below command in the terminal.

`xcrun simctl openurl booted {your_URL_here}`

##### Option 2: Universal links

[Universal links](https://developer.apple.com/ios/universal-links/) are a more modern way of handling deep links and are recommended by Apple.
They are more secure and provide a better user experience. However, unlike URL schemes they require a bit more setup that is highlighted in [these](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html) Apple docs.

Once you have the setup from the Apple docs in place you will need to modify the push open tracking as described below:

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let handled = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: completionHandler) { url in
            print("deep link is ", url)
        }
        if !handled {
           // not a klaviyo notification should be handled by other app code
        }
    }
}
```

Note that the deep link handler will be called back on the main thread. If you want to handle URL schemes in addition to universal links you implement them as described in [Option 1: URL Schemes](#option-1-URL-schemes).

#### Rich Push

>  ℹ️ Rich push notifications are supported in SDK version [2.2.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/2.2.0) and higher

[Rich Push](https://help.klaviyo.com/hc/en-us/articles/16917302437275) is the ability to add images to push notification messages.  Once the steps
in the [Installation](#installation) section are complete, you should have a notification service extension in your
project setup with the code from the `KlaviyoSwiftExtension`. Below are instructions on how to test rich push notifications.

##### Testing rich push notifications

* To test rich push notifications, you will need three things:
  * Any push notifications tester like Apple's official [push notification console](https://developer.apple.com/notifications/push-notifications-console/) or a third party software such as [this](https://github.com/onmyway133/PushNotifications).
* A push notification payload that resembles what Klaviyo would send to you. The below payload should work as long as the image is valid:

```json
{
  "aps": {
    "alert": {
      "title": "Sample title for a Klaviyo push notification,
      "body": "Sample body for a Klaviyo push notification"
    },
    "mutable-content": 1
  },
  "rich-media": "https://picsum.photos/200/300.jpg",
  "rich-media-type": "jpg"
}
```
  * A real device's push notification token. This can be printed out to the console from the `didRegisterForRemoteNotificationsWithDeviceToken` method in `AppDelegate`.

Once you have these three things, you can then use the push notifications tester and send a local push notification to make sure that everything was set up correctly.

#### Badge Count
>  ℹ️ Setting or incrementing the badge count is available in SDK version [4.1.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/4.1.0) and higher

Klaviyo supports setting or incrementing the badge count when you send a push notification. For this functionality to work, you must set up the Notification Service Extension and an App Group as outlined under the [Installation](#installation) section.

##### Autoclearing

By default, the Klaviyo SDK automatically clears the badge count on app open. If you want to disable this behavior, add a new entry for `klaviyo_badge_autoclearing` as a Boolean set to `NO` in your app's `Info.plist`. You can re-enable automatically clearing badges by setting this value to `YES`.

##### Handling Other Badging Sources

Klaviyo SDK will automatically handle the badge count associated with Klaviyo pushes. If you need to manually update the badge count to account for other notification sources, use the `KlaviyoSDK().setBadgeCount(:)` method, which will update the badge count and keep it in sync with the Klaviyo SDK. This method should be used instead of (rather than in addition to) setting the badge count using `UNUserNotificationCenter` and/or `UIApplication` methods.

#### Silent Push Notifications

Silent push notifications (also known as background pushes) allow your app to receive payloads from Klaviyo without displaying a visible alert to the user. These are typically used to trigger background behavior, such as displaying content, personalizing the app interface, or downloading new information from a server.
>  ℹ️ Silent push support is available by default. The Klaviyo SDK does not provide specific handling for silent push notifications. See [enable the remote notifications capability](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app#Enable-the-remote-notifications-capability) and [receive background notifications](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app#Enable-the-remote-notifications-capability) for more details.

To handle silent push notifications in your app, you'll need to implement the appropriate delegate methods yourself. Here's an example of how to handle silent push notifications:

```
func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
  // Access custom key-value pairs from the top level
  if let customData = userInfo["key_value_pairs"] as? [String: String] {
    // Process your custom key-value pairs here
    for (key, value) in kvPairs {
        print("Key: \(key), Value: \(value)")
    }
  } else {
      print("No key_value_pairs found in notification")
  }
}
```

>  ℹ️ Silent push notifications are not supported by the iOS simulator. To test silent push notifications, please use a real device.

#### Custom Data
Klaviyo messages can also include key-value pairs (custom data) for both standard and silent push notifications. You can access these key-value pairs using the `key_value_pairs` key on the [`userInfo`](https://developer.apple.com/documentation/foundation/nsnotification/1409222-userinfo) dictionary associated with the notification (for silent pushes, see the example above; for standard pushes, see [`NotificationService.swift`](https://github.com/klaviyo/klaviyo-swift-sdk/blob/master/Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift) in the example app). This enables you to extract additional information from the push payload and handle it appropriately - for instance, by triggering background processing, logging analytics events, or dynamically updating app content.

## In-App Forms
> ℹ️ In-App Forms support is available in SDK version [4.2.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/4.2.0) and higher

[In-App Forms](https://help.klaviyo.com/hc/en-us/articles/34567685177883) are messages displayed to mobile app users while they are actively using an app. You can create new In-App Forms in a drag-and-drop editor in the Sign-Up Forms tab in Klaviyo.  Follow the instructions in this section to integrate forms with your app. The SDK will
display forms according to their targeting and behavior settings and collect delivery and engagement analytics automatically.

Beginning with version 5.0.0, In-App Forms supports advanced targeting and segmentation. In your Klaviyo account, you can configure forms to target or exclude specific lists or segments, and the form will only be shown to users matching those criteria, based on their profile identifiers configured via the [`KlaviyoSDK().set(...)` methods](https://github.com/klaviyo/klaviyo-swift-sdk/blob/61e64552ad2acb65985e9305ae56eb57ff38d28b/Sources/KlaviyoSwift/Klaviyo.swift#L69-L135).

### Prerequisites

* Using Klaviyo SDK version 4.2.0 and higher
* Imported `KlaviyoSwift` and `KlaviyoForms` SDK modules and adding it to the app target.
* We strongly recommend using the latest version of the SDK to ensure compatibility with the latest In-App Forms features. The minimum SDK version supporting In-App Forms is `4.2.0`, and a feature matrix is provided below. Forms that leverage unsupported features will not appear in your app until you update to a version that supports those features.
* Please read the [migration guide](MIGRATION_GUIDE.md) if you are upgrading from 4.2.0-4.2.1 to understanding changes to In-App Forms behavior.

| Feature            | Minimum SDK Version |
|--------------------|---------------------|
| Basic In-App Forms | 4.2.0+              |
| Time Delay         | 5.0.0               |
| Audience Targeting | 5.0.0               |

### Setup

To configure your app to display In-App Forms, call `Klaviyo.registerForInAppForms()` after initializing the SDK with your public API key. Once registered, the SDK may launch an overlay view at any time to present a form according to its targeting and behavior settings configured in your Klaviyo account.

For the best user experience, we recommend registering after any splash screen or loading animations have completed. Depending on your app's architecture, this might be in your AppDelegate's `application(_:didFinishLaunchingWithOptions:)` method.

```swift
import KlaviyoSwift
import KlaviyoForms
...

// if registering in the same location where you're initializing the SDK
KlaviyoSDK()
    .initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
    .registerForInAppForms()

// if registering elsewhere after `KlaviyoSDK` is initialized
KlaviyoSDK().registerForInAppForms()
```

Note that the In-App Forms will automatically respond if/when the API key and/or the profile data changes. You do not need to re-register.

#### In-App Forms Session Configuration

A "session" is considered to be a logical unit of user engagement with the app, defined as a series of foreground interactions that occur within a continuous or near-continuous time window. This is an important concept for In-App Forms, as we want to ensure that a user will not see a form multiple times within a single session.

A session will time out after a specified period of inactivity. When a user launches the app, if the time between the previous interaction with the app and the current one exceeds the specified timeout, we will consider this a new session.

This timeout has a default value of 3600 seconds (1 hour), but it can be customized. To do so, pass an `InAppFormsConfig` object to the `registerForInAppForms()` method. For example, to set a session timeout of 30 minutes:

```swift
import KlaviyoForms
// e.g. to configure a session timeout of 30 minutes
let config = InAppFormsConfig(sessionTimeoutDuration: 1800)
KlaviyoSDK().registerForInAppForms(configuration: config)
```

### Unregistering from In-App Forms

If at any point you need to prevent the SDK from displaying In-App Forms, e.g. when the user logs out, you may call:

```swift
import KlaviyoForms
KlaviyoSDK().unregisterFromInAppForms()
```

Note that after unregistering, the next call to `registerForInAppForms()` will be considered a new session by the SDK.


### Deep linking

Deep linking to a particular screen based on user action from an In-App Form is similar to handling deep links originating from push notifications. [Step 3](#step-3-implement-handling-deep-links-in-your-app) of the deep linking section outlines exactly how this can be achieved. For further information on how the deep link is handled, see [Apple's documentation](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)).

## Additional Details

### Sandbox Support

> ℹ️ Sandbox support is available in SDK version [2.2.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/2.2.0) and higher

Apple has two environments with push notification support - Production and Sandbox.
The Production environment supports sending push notifications to real users when an app is published in the App Store or TestFlight.
In contrast, Sandbox applications that support push notifications are those signed with iOS Development Certificates, instead of iOS Distribution Certificates.
Sandbox acts as a staging environment, allowing you to test your applications in a environment similar to but distinct from Production without having to worry about sending messages to real users.

Our SDK supports the use of Sandbox for push as well.
Klaviyo's SDK will determine and store the environment that your push token belongs to and communicate that to our backend,
allowing your tokens to route sends to the correct environments. There is no additional setup needed.
As long as you have deployed your application to Sandbox with our SDK employed to transmit push tokens to our backend,
the ability to send and receive push on these Sandbox applications should work out-of-the-box.

### SDK Data Transfer
Starting with version 1.7.0, the SDK will cache incoming data and flush it back to the Klaviyo API on an interval.
The interval is based on the network link currently in use by the app. The table below shows the flush interval used for each type of connection:

| Network   | Interval   |
| :-------- | :--------- |
| WWAN/Wifi | 10 seconds |
| Cellular  | 30 seconds |

Connection determination is based on notifications from our reachability service.
When there is no network available, the SDK will cache data until the network becomes available again.
All data sent by the SDK should be available shortly after it is flushed by the SDK.

### Retries
The SDK will retry API requests that fail under certain conditions. For example, if a network timeout occurs, the request will be retried on the next flush interval.
In addition, if the SDK receives a rate limiting error `429` from the Klaviyo API, it will use exponential backoff with jitter to retry the next request.

## Contributing
See the [contributing guide](.github/CONTRIBUTING.md) to learn how to contribute to the Klaviyo Swift SDK.
We welcome your feedback in the [issues](https://github.com/klaviyo/klaviyo-swift-sdk/issues) section of our public GitHub repository.

### License
KlaviyoSwift is available under the MIT license. See the LICENSE file for more info.
