# klaviyo-swift-sdk

![CI status](https://github.com/klaviyo/klaviyo-swift-sdk/actions/workflows/swift.yml/badge.svg)
[![Swift](https://img.shields.io/badge/Swift-5.6_5.7-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.6_5.7-Orange?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![Platform](https://img.shields.io/cocoapods/p/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)

## Contents

- [klaviyo-swift-sdk](#klaviyo-swift-sdk)
- [Contents](#contents)
  - [Overview](#overview)
  - [Installation](#installation)
  - [Initialization](#initialization)
  - [Profile Identification](#profile-identification)
    - [Reset Profile](#reset-profile)
    - [Anonymous Tracking Notice](#anonymous-tracking-notice)
  - [Event tracking](#event-tracking)
  - [Push Notifications](#push-notifications)
    - [Prerequisites](#prerequisites)
    - [Setup](#setup)
    - [Collecting Push Token](#collecting-push-token)
    - [Request push notification permission](#request-push-notification-permission)
    - [Receiving push notifications and tracking opens](#receiving-push-notifications-and-tracking-opens)
    - [Rich push notifications](#rich-push-notifications)
  - [Deep Linking](#deep-linking)
  - [Additional Details](#additional-details)
    - [SDK Data Transfer](#sdk-data-transfer)
    - [Retries](#retries)
    - [License](#license)
    - [UserDefaults access (SDK version < 3.0.0)](#userdefaults-access-sdk-version--300)

## Overview

The Klaviyo Swift SDK allows developers to incorporate Klaviyo's analytics and push notification functionality in their iOS applications.
The SDK assists in identifying users and tracking events via the latest [Klaviyo client APIs](https://developers.klaviyo.com/en/reference/api_overview).
Top reduce performance overhead, API requests are queued and sent in batches. The queue is persisted to local storage so that data is not lost if the device is offline or the app is terminated.

Once integrated, your marketing team will be able to better understand your app users' needs and send them timely messages via APNs.

## Installation

<details>
<summary>Swift Package Manager</summary>

KlaviyoSwift is available via [Swift Package Manager](https://swift.org/package-manager). Follow the steps below to install.

1. Open your project and navigate to your project’s settings.
2. Select the **Swift Packages** tab and click on the **add** button below the packages list.
3. Enter the URL of the Swift SDK repository `https://github.com/klaviyo/klaviyo-swift-sdk` in the text field and click **Next**.
4. On the next screen, select the latest SDK version and click **Next**.
5. Select the `KlaviyoSwift` package.
6. Click **Finish**.
</details>

<details>

<summary>CocoaPods</summary>

KlaviyoSwift is available through [CocoaPods](https://cocoapods.org/?q=klaviyo).

1. To install, add the following line to your Podfile:

```ruby
pod "KlaviyoSwift"
```

2. Run `pod install` to complete the integration.

The library can be kept up-to-date via `pod update`.

</details>

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

These above Identifiers are persisted to local storage so that the SDK can keep track of the current user/profile for you when you make event requests or want to set a push token etc.

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
<TODO: Should we talk about what happens to a push token here?>

```swift
// start a profile for Blob Jr.
let profile = Profile(email: "junior@blob.com",  firstName: "Blob",  lastName: "Jr.")
KlaviyoSDK().set(profile: profile)

// stop tracking Blob Jr.
KlaviyoSDK().resetProfile()

// start a profile for Robin Hood
let profile = Profile(email: "junior@blob.com",  firstName: "Robin",  lastName: "Hood")
KlaviyoSDK().set(profile: profile)
```
### Anonymous Tracking Notice

By default, Klaviyo will begin tracking unidentified users in your app when a push token is set or we receive an event to track.
This means you will be able to track events or set a push notifications token from users in your app without any user information provided.
When an email or other primary identifier is provided, Klaviyo will merge the data from the anonymous user to a new identified user.

Prior to version 1.7.0, the Klaviyo SDK used the [Apple identifier for vendor (IDFV)](https://developer.apple.com/documentation/uikit/uidevice/1620059-identifierforvendor) to facilitate anonymous tracking.
Starting with version 1.7.0, the SDK will use a cached UUID that is generated when the SDK is initialized.
For existing anonymous profiles using IDFV, the SDK will continue to use IDFV, instead of generating a new UUID.

## Event tracking

The SDK provides tools for tracking events that users perform on your app via the [Create Client Event API](https://developers.klaviyo.com/en/reference/create_client_event).
A list of common Klaviyo defined event metrics can be found in `Event.EventName`. You can also create custom events by using the `CustomEvent` enum case of `Event.EventName`.

```swift
// using a predefined event name
let event = Event(name: .StartedCheckoutMetric,
                      properties: [
                        "product.1": "t-shirt.99",
                        "product.2": "pants.67",
                      ],
                      value: 166
    )

KlaviyoSDK().create(event: event)

// using a custom event name
let event = Event(name: .CustomEvent("Checkout Completed"),
                      properties: [
                        "product.1": "t-shirt.99",
                        "product.2": "pants.67",
                      ],
                      value: 166
    )
```

### Arguments

The `create` method takes an event object as an argument. The event can be constructed with the following arguments:
- `name`: The name of the event you want to track, as a EventName enum. The are a number of commonly used event names provided by default. If you need to log an event with a different name use `CustomEvent` with a string of your choosing. This argument is required to track an event.
- `properties`: An dictionary of properties that are specific to the event. This argument is optional.
- `value`: A numeric value (`Double`) to associate with this event. For example, the dollar amount of a purchase.

## Push Notifications

### Prerequisites

* An apple developer account.
* Configure [iOS push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971) in Klaviyo account settings.

### Setup

* Enable push notification capabilities in your Xcode project. The section "Enable the push notification capability" in this [Apple developer guide](https://developer.apple.com/documentation/usernotifications/registering_your_app_with_apns#2980170) provides detailed instructions.
* If you intend to use rich push notifications add a [Notification service extension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension) to your xcode project.
A notification service app extension ships as a separate bundle inside your iOS app. To add this extension to your app:
  * Select File > New > Target in Xcode.
  * Select the Notification Service Extension target from the iOS > Application extension section.
  * Click Next.
  * Specify a name and other configuration details for your app extension.
  * Click Finish.

> ⚠️ By default the deployment target of your notification service extension might be the latest iOS version and not
the minimum you want to support. This may cause push notifications to not show the attached media in devices whose
iOS versions are lower than the deployment target of the notification service extension. ⚠️

### Collecting Push Token

In order to send push notifications to your users, you must collect their push tokens and register them with Klaviyo.
This is done via the `KlaviyoSDK().set(pushToken:)` method, which registers push token and current authorization state
via the [Create Client Push Token API](https://developers.klaviyo.com/en/reference/create_client_push_token).

* Call [`registerForRemoteNotifications()`](https://developer.apple.com/documentation/uikit/uiapplication/1623078-registerforremotenotifications)
on `UIApplication` instance to request a push token from APNs. Ex: `UIApplication.shared.registerForRemoteNotifications()`. This is typically done in the `application:didFinishLaunchingWithOptions:` method of your app delegate.
* Implement the `application:didRegisterForRemoteNotificationsWithDeviceToken` method in your app delegate to receive the push token from APNs and register it with Klaviyo.
>  ℹ️ Please note that the KlaviyoSDK should be initialized prior to calling any SDK methods.

```swift
import KlaviyoSwift


func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    KlaviyoSDK().set(pushToken: deviceToken)
}
```
#### Push tokens and multiple profiles

Klaviyo SDK will disassociate the device push token from the current profile whenever it is reset by calling
`set(profile:)` or `resetProfile`. You should call `set(pushToken:)` again after resetting the currently tracked profile
to explicitly associate the device token to the new profile.

### Request push notification permission

In order to send push notifications to your users, you must request permission to send push notifications.
Add the following code to your application wherever you would like to prompt users to register for push notifications.
This is often included within `application:didFinishLaunchingWithOptions:` in the application delegate file, but it can be placed elsewhere as well.

```swift
	import UserNotifications
	...
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

	    // Enable or disable features based on the authorization status.
	    // if you didn't register for remote notifications above you can call `registerForRemoteNotifications` here
	    // Klaviyo SDK will automatically update the authorization status on next app launch
	}
```

### Receiving push notifications and tracking opens
Implement the [`userNotificationCenter:didReceive:withCompletionHandler`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/1649501-usernotificationcenter)
and [`userNotificationCenter:willPresent:withCompletionHandler`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/1649518-usernotificationcenter) to handle push notifications received whe the app is in the background and foreground.
method in your app delegate to track when a user opens a push notification. This will handle tracking opens for when the app is backgrounded and the user taps on the notification.
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

To read more about push notifications, check out our additional push notification guides.

- [How to set up push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971)
- [How to send a push notification campaign](https://help.klaviyo.com/hc/en-us/articles/360006653972)
- [How to add a push notification to a flow](https://help.klaviyo.com/hc/en-us/articles/12932504108571)

TODO: move this - Once your first push notifications are sent and opened, you should start to see _Opened Push_ metrics within your Klaviyo dashboard.

#### Rich push notifications

> :warning: **Rich push notifications are supported in SDK version [2.2.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/2.2.0) and higher**

Rich push notification is the ability to add images to your push notification messages that Apple has supported since iOS 10.
In order to do this Apple requires your app to implement a [Notification service extension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension).
Following the below steps should help set up your app to receive rich push notifications.

* Implement the notification service app extension: The notification service app extension is responsible for downloading the media resource and attaching it to the push notification.
You should see a file called `NotificationService.swift` under the notification service extension target (created during setup).
From here on depending on which dependency manager you use the steps would look slightly different:

<details>
<summary> Swift Package Manager(SPM) </summary>

- Tap on the newly created notification service extension target
  - Under General > Frameworks and libraries add `KlaviyoSwiftExtension` using the + button at the bottom left.
  - Then in the `NotificationService.swift` file add the code for the two required delegates from [this](Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift) file. This sample covers calling into Klaviyo so that we can download and attach the media to the push notification.
</details>

<details>
<summary> Cocoapods </summary>

- In your `Podfile` add in `KlaviyoSwiftExtension` as a dependency to the newly added notification service extension target.

  Example:

  ```
  target 'NotificationServiceExtension' do
      pod 'KlaviyoSwiftExtension', '2.1.0-beta1'
  end
  ```

  Be sure to replace the name of your notification service extension target above.

  - Once you've added in the dependency make sure to `pod install`.
  - Then in the `NotificationService.swift` file add the code for the two required delegates from [this](Examples/KlaviyoSwiftExamples/CocoapodsExample/NotificationServiceExtension/NotificationService.swift) file. This sample covers calling into Klaviyo so that we can download and attach the media to the push notification.
</details>

* Test your rich push notifications
  * Any push notifications tester like apple official [push notification console](https://developer.apple.com/notifications/push-notifications-console/) or a third party software such as [this](https://github.com/onmyway133/PushNotifications).
  * A push notification payload that resembles what Klaviyo would send to you. The below payload should work as long as the image is valid:

    ```json
    {
    "aps": {
    "alert": {
      "title": "Free apple vision pro",
      "body": "Free Apple vision pro when you buy a Klaviyo subscription."
    },
    "mutable-content": 1
    },
    "rich-media": "https://www.apple.com/v/apple-vision-pro/a/images/overview/hero/portrait_base__bwsgtdddcl7m_large.jpg",
    "rich-media-type": "jpg"
    }
    ```
  * A real device's push notification token. This can be printed out to the console from the `didRegisterForRemoteNotificationsWithDeviceToken` method in `AppDelegate`.
  * Once we have these three things we can then use the push notifications tester and send a local push notification to make sure that everything was set up correctly.

## Deep Linking

> :warning: **Your app needs to use version 1.7.2 at a minimum in order for the below steps to work.**

There are two use cases for deep linking that can be relevant here:

1. When you push a notification to your app with a deep link.
2. Any other cases where you may want to deep link into your app via SMS, email, web browser etc.

In order for deep linking to work, there are a few configurations that are needed and these are no different from what are required for handling deep linking in general and [Apple documentation](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app) on this can be followed in conjunction with the steps highlighted here:

### Option 1: Modify Open Tracking

If you plan to use universal links in your app for deep linking you will need to modify the push open tracking as described below:

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

Note that the deep link handler will be called back on the main thread. If you want to handle uri schemes in addition to universal links you implement them as described below.

### Option 2: Use URL Schemes

If you do not need universal link support you can instead implement url schemes for your app and the deepLinkHandler as indicated in Option 1 can be omitted. The Klaviyo SDK will follow all url automatically in this case.

#### Step 1: Register the URL scheme

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

#### Step 2: Whitelist supported URL schemes

Since iOS 9 Apple has mandated that the URL schemes that your app can open need to also be listed in the Info.plist. This is in addition to Step 1 above. Even if your app isn't opening any other apps, you still need to list your app's URL scheme in order for deep linking to work.

This needs to be done in the Info.plist directly:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
	<string>{your custom URL scheme}</string>
</array>
```

#### Step 3: Implement handling deep links in your app

Steps 1 & 2 set your app up for receiving deep links but now is when you need to figure out how to handle them within your app.

If you are using UIKit, you need to implement [`application:openURL:options:`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application) in your application's app delegate.

Finally, we have an example app (`Examples/KlaviyoSwiftExamples`) in the SDK repo that you can reference to get an example of how to implement deep links in your app.

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

Once the above steps are complete, you can send push notifications from the Klaviyo Push editor within the Klaviyo website. Here you can build and send a push notification through Klaviyo to make sure that the URL shows up in the handler you implemented in Step 3.

Additionally, you can also locally trigger a deep link to make sure your code is working using the below command in the terminal.

`xcrun simctl openurl booted {your_URL_here}`


#### Sandbox Support

Apple has two environments with push notification support - production and Sandbox. The Production environment supports sending push notifications to real users when an app is published in the App Store or TestFlight. In contrast, Sandbox applications that support push notifications are those signed with iOS Development Certificates, instead of iOS Distribution Certificates. Sandbox acts as a staging environment, allowing you to test your applications in a environment similar to but distinct from production without having to worry about sending messages to real users.

Our SDK supports the use of Sandbox for push as well. Klaviyo's SDK will determine and store the environment that your push token belongs to and communicate that to our backend, allowing your tokens to route sends to the correct environments. There is no additional setup needed. As long as you have deployed your application to Sandbox with our SDK employed to transmit push tokens to our backend, the ability to send and receive push on these Sandbox applications should work out-of-the-box.
#### Testing with Klaviyo

At this point unfortunately we don't support testing debug builds with Klaviyo. So if you are trying to send a test push notification to a debug build you'll see an error on Klaviyo.

A suggested temporary workaround would be creating a test flight build with the above changes required for rich push notifications, performing some actions on the test flight build to identify the device and making sure you are able to see that device in Klaviyo. Once you have that device's push token in any profile you can create a list or segment with that profile and send a push campaign with an image to test the full end-to-end integration.

## Additional Details

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

### License
KlaviyoSwift is available under the MIT license. See the LICENSE file for more info.

### UserDefaults access (SDK version < 3.0.0)
As of fall 2023, Apple requires apps that access specific Apple APIs to provide a reason for this access.
Previous versions of the Klaviyo SDK used UserDefaults to store data about the current user.
Today, when the SDK starts up, it must access this data to migrate to a new format.
Below, we've provided a sample reason you can include with your app submission (if requested):

> UserDefaults is accessed by the Klaviyo SDK within our app to migrate some user data (previously stored there). None of this data is shared with other apps.


If your app or other SDKs also access UserDefaults, you may need to amend the reason to include that usage as well.
Use the string NSPrivacyAccessedAPICategoryUserDefaults as the value for the NSPrivacyAccessedAPIType key in your NSPrivacyAccessedAPITypes dictionary.
For more information, see this [guide](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api#4278401).
