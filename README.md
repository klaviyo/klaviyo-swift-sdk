# KlaviyoSwift

[![CI Status](https://travis-ci.org/klaviyo/klaviyo-swift-sdk.svg?branch=master)](https://travis-ci.org/klaviyo/klaviyo-swift-sdk)
[![Swift](https://img.shields.io/badge/Swift-5.6_5.7-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.6_5.7-Orange?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![Platform](https://img.shields.io/cocoapods/p/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)

## DISCLAIMER

*This project is in a closed beta,
breaking changes could still be made to the API.
This is not yet intended for public use*

## Overview

KlaviyoSwift is an SDK, written in Swift that can be integrated into your iOS App. The SDK enables you to engage with your customers using push notifications. In addition you will be able to take advantage of Klaviyo's identification and event tracking functionality. Once integrated, your marketing team will be able to better understand your app users' needs and send them timely messages via APNs.

### Installation options

1. [Install with SPM](#install-with-spm)
1. [Install with Cocoapods](#install-with-cocoapods)

## [Install with SPM](#install-with-spm)
KlaviyoSwift is available via [Swift Package Manager (SPM)](https://swift.org/package-manager/). Follow the steps below to install.

1. Open your project and navigate to your project’s settings.
2. Select the **Swift Packages** tab and click on the **add** button below the packages list.
3. Enter the URL of the Swift SDK repository `https://github.com/klaviyo/klaviyo-swift-sdk` in the text field and click **Next**.
4. On the next screen, select the latest SDK version and click **Next**.
5. Select the `KlaviyoSwift` package.
6. Click **Finish**.

## [Install with CocoaPods](#install-with-cocoapods)
KlaviyoSwift is available through [CocoaPods](https://cocoapods.org/?q=klaviyo).

1. To install, add the following line to your Podfile:

```ruby
pod "KlaviyoSwift"
```

2. Run `pod install` to complete the integration.

The library can be kept up-to-date via `pod update`.


## Event tracking
After the SDK is installed you can begin tracking events in your app.

1. Make sure any .swift files using the Klaviyo SDK contain the following import call:

```swift
import KlaviyoSwift
```

2. To add Klaviyo's tracking functionality, include the following line in AppDelegate.swift, within `application:didFinishLaunchingWithOptions`:

```swift
KlaviyoSDK().initalize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
```

3. Begin tracking events anywhere within your application by calling the `create(event:)` method in the relevant location.

```swift
let klaviyo = KlaviyoSDK()

let event = Event(name: .StartedCheckout, properties: [
    "Total Price": 10.99,
    "Items Purchased": ["Hot Dog", "Fries", "Shake"]
], identifiers: .init(email: "junior@blob.com"),
profile: [
    "$first_name": "Blob",
    "$last_name": "Jr"
], value: 10.99)

klaviyo.create(event: event)
```
### Arguments

The `create` method takes an event object as an argument. The event can be constructed with the following arguments:

* `name`: The name of the event you want to track, as a EventName enum.  The are a number of commonly used event names provided by default. If you need to log an event with a different name use `CustomEvent` with a string of your choosing. This argument is required to track an event.

* `profile`: An dictionary of properties that belong to the person who did the action you're tracking. Including an `$email`, `$phone_number` or `$id` key associates the event with particular profile in Klaviyo. In addition the SDK will retain these properties for use in future sdk calls, therefore if they are not included previously set identifiers will be used to log the event. This argument is optional.

* `properties`: An dictionary of properties that are specific to the event. This argument is optional.

* `time`: This is the timestamp, as an `Date`, when the event occurred. This argument is optional but recommended if you are tracking past events. If you're tracking real- time activity, you can ignore this argument.

* `value`: A numeric value (`Double`) to associate with this event. For example, the dollar amount of a purchase.

## Identifying traits of people

If you app collects additional identifying traits about your users you can provide this to Klaviyo via the `set(profileAttribute:value:)` or `set(profile:) methods and via the . In both cases we've provided a wide array of commonly used profile properties you can use. If you need something more custom though you can always pass us those properties via the properties dictionary when you create your profile object.

```swift
let profile = Profile(email: "junior@blob.com", firstName: "Blob", lastName: "Jr")
KlaviyoSDK().set(profile: profile)

// or setting individual properties
KlaviyoSDK().set(profileAttribute: .firstName, "Blob")
KlaviyoSDK().set(profileAttribute: .lastName, "Jr")
```


Note that the only argument `set(profile:)` takes is a dictionary representing a customer's attributes. This is different from `trackEvent`, which can take multiple arguments.


## Anonymous Tracking Notice

By default, Klaviyo will begin tracking unidentified users in your app once the SDK is initialized. This means you will be able to track events from users in your app without any user information provided. When an email or other primary identifier is provided, Klaviyo will merge the data from the anonymous user to a new identified user.

Prior to version 1.7.0, the Klaviyo SDK used the [Apple identifier for vendor (IDFV)](https://developer.apple.com/documentation/uikit/uidevice/1620059-identifierforvendor) to facilitate anonymous tracking. Starting with version 1.7.0, the SDK will use a cached UUID that is generated when the SDK is initialized. For existing anonymous profiles using IDFV, the SDK will continue to use IDFV, instead of generating a new UUID.

## Profile properties and Identifiers

Whenever an email (or other identifier) is provided to use via our APIs we will retain that information for future calls so that new data is tracked against the right profile. However, you are always free to override the current identifiers by passing new ones into a customer properties dictionary.

```swift
KlaviyoSDK().set(email: "junior@blob.com")
```

## Push Notifications

Implementing push notifications requires a few additional snippets of code to enable.:
1. Registering users for push notifications.
2. Sending resulting push tokens to Klaviyo.
3. Handlinge when users attempt to open your push notifications.

### Sending push notifications

1. Add the following code to your application wherever you would like to prompt users to register for push notifications. This is often included within `application:didFinishLaunchingWithOptions:`, but it can be placed elsewhere as well. When this code is called, ensure that the Klaviyo SDK is configured and that `set(email:)` is called. This enables Klaviyo to match app tokens with profiles in Klaviyo customers.

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
	}

	UIApplication.shared.registerForRemoteNotifications()
```

2. Add the following code to the application delegate file in  `application:didRegisterForRemoteNotificationsWithDeviceToken`. You may need to add this code to your application delegate if you have not done so already.

```swift
    func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        KlaviyoSDK().set(pushToken: deviceToken)
    }
```

Any users that enable/accept push notifications from your app now will be eligible to receive your custom notifications.

To read more about sending push notifications, check out our additional push notification guides.
* [How to set up push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971)
* [How to send a push notification campaign](https://help.klaviyo.com/hc/en-us/articles/360006653972)
* [How to add a push notification to a flow](https://help.klaviyo.com/hc/en-us/articles/12932504108571)

### Tracking push notifications

The following code example allows you to track when a user opens a push notification.

1. Add the following code that extends your app delegate:

```swift
    extension AppDelegate: UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
            let handled = KlaviyoSDK().handle(notificationResponse: response, completionHandler: completionHandler)
            if not handled {
               // not a klaviyo notification should be handled by other app code
            }
        }
    }

```

Once your first push notifications are sent and opened, you should start to see *Opened Push* metrics within your Klaviyo dashboard.

### Foreground push handling

The following code example allows push notifications to be displayed when your app is running:

```swift

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  willPresent notification: UNNotification,
                                  withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions =  [.alert]
        if #available(iOS 14.0, *) {
          options = [.list, .banner]
        }
        completionHandler(options)
    }
```

If a user taps on the notification with the application open, this event is tracked as an *Opened Push* event.

## Handling deep linking

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
            let handled = KlaviyoSDK().handle(notificationResponse: response, completionHandler: completionHandler) { url in
               // parse deep link and navigate here.
            }
            if not handled {
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

If you are using SwiftUI, then you can implement [`onOpenURL(perform:)`](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)) as a view modifier in the view you intent to handle deep links. This may or may not be the root of your scene.

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

## SDK Data Transfer

Starting with version 1.7.0, the SDK will cache incoming data and flush it back to the Klaviyo API on an interval. The interval is based on the network link currently in use by the app. The table below shows the flush interval used for each type of connection:

| Network     | Interval    |
| :---        | :--- |
| WWAN/Wifi   | 10 seconds  |
| Cellular    | 30 seconds  |


Connection determination is based on notifications from our reachability service. When there is no network available, the SDK will cache data until the network becomes available again. All data sent by the SDK should be available shortly after it is flushed by the SDK.


### Retries

The SDK will retry API requests that fail under certain conditions. For example, if a network timeout occurs, the request will be retried on the next flush interval. In addition, if the SDK receives a rate limiting error `429` from the Klaviyo API, it will use exponential backoff with jitter to retry the next request.

## License

KlaviyoSwift is available under the MIT license. See the LICENSE file for more info.
