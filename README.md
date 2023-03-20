# KlaviyoSwift

[![CI Status](https://travis-ci.org/klaviyo/klaviyo-swift-sdk.svg?branch=master)](https://travis-ci.org/klaviyo/klaviyo-swift-sdk)
[![Swift](https://img.shields.io/badge/Swift-5.6_5.7-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.6_5.7-Orange?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![Platform](https://img.shields.io/cocoapods/p/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)


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
Klaviyo.setupWithPublicAPIKey(apiKey: "YOUR_KLAVIYO_PUBLIC_API_KEY")
```

3. Begin tracking events anywhere within your application by calling the `trackEvent` method in the relevant location.

```swift

let klaviyo = Klaviyo.sharedInstance

let customerDictionary : NSMutableDictionary = NSMutableDictionary()
customerDictionary[klaviyo.KLPersonEmailDictKey] = "john.smith@example.com"
customerDictionary[klaviyo.KLPersonFirstNameDictKey] = "John"
customerDictionary[klaviyo.KLPersonLastNameDictKey] = "Smith"

let propertiesDictionary : NSMutableDictionary = NSMutableDictionary()
propertiesDictionary["Total Price"] = 10.99
propertiesDictionary["Items Purchased"] = ["Milk","Cheese", "Yogurt"]
Klaviyo.sharedInstance.trackEvent(
    eventName: "Completed Checkout",
    customerProperties: customerDictionary,
    properties: propertiesDictionary
)
```
### Arguments

The `track` function can be called with up to four arguments.

* `eventName`: The name of the event you want to track, as a string. This argument is required to track an event.

* `customerProperties`: An NSDictionary of properties that belong to the person who did the action you're tracking. If you do not include an `$email`, `$phone_number` or `$id key`, the event cannot be tracked by Klaviyo. This argument is optional but recommended.

* `properties`: An NSDictionary of properties that are specific to the event. This argument is optional.

* `eventDate`: This is the timestamp, as an NSDate, when the event occurred. This argument is optional but recommended if you are tracking past events. If you're tracking real- time activity, you can ignore this argument.

## Identifying traits of people

You can identify traits about a person using `trackPersonWithInfo`.

```swift
let klaviyo = Klaviyo.sharedInstance

let personInfoDictionary : NSMutableDictionary = NSMutableDictionary()
personInfoDictionary[klaviyo.KLPersonEmailDictKey] = "john.smith@example.com"
personInfoDictionary[klaviyo.KLPersonZipDictKey] = "02215"


klaviyo.trackPersonWithInfo(personDictionary: personInfoDictionary)
```

Note that the only argument `trackPersonWithInfo` takes is a dictionary representing a customer's attributes. This is different from `trackEvent`, which can take multiple arguments.


## Anonymous Tracking Notice

By default, Klaviyo will begin tracking unidentified users in your app once the SDK is initialized. This means you will be able to track events from users in your app without any user information provided. When an email or other primary identifier is provided, Klaviyo will merge the data from the anonymous user to a new identified user. 

Prior to version 1.7.0, the Klaviyo SDK used the [Apple identifier for vendor (IDFV)](https://developer.apple.com/documentation/uikit/uidevice/1620059-identifierforvendor) to facilitate anonymous tracking. Starting with version 1.7.0, the SDK will use a cached UUID that is generated when the SDK is initialized. For existing anonymous profiles using IDFV, the SDK will continue to use IDFV, instead of generating a new UUID.

## Special properties

The following special properties can be used when identifying a user or tracking event:
    
*    `KLPersonEmailDictKey`
*    `KLPersonFirstNameDictKey`
*    `KLPersonLastNameDictKey`
*    `KLPersonPhoneNumberDictKey`
*    `KLPersonTitleDictKey`
*    `KLPersonOrganizationDictKey`
*    `KLPersonCityDictKey`
*    `KLPersonRegionDictKey`
*    `KLPersonCountryDictKey`
*    `KLPersonZipDictKey`
*    `KLEventIDDictKey`
*    `KLEventValueDictKey`

In cases where you wish to call `trackEvent` with only the `eventName` parameter, you can use `setUpUserEmail` to configure your user's email address. This allows you to avoid anonymous user tracking.

By calling `setUpUserEmail` once, usually upon application login, Klaviyo can track all subsequent events as tied to the given user. However, you are also free to override this functionality by passing in a customer properties dictionary.

```swift
    Klaviyo.sharedInstance.setUpUserEmail(userEmail: "john.smith@example.com")
```

## Integrating with Shopify's Mobile SDK
If your application makes use of Shopify's Mobile Buy SDK, then Klaviyo can easily port that data into your Klaviyo account. Simply add the following line of code to your app within your Shopify completion handler or wherever your checkout code creates Shopify's `BuyCheckout` instance (if it is within the completion handler, it should be referenced as `checkout`. If you are building the checkout object manually then use whichever name you created):

` Klaviyo.sharedInstance.setUpUserEmail(userEmail: checkout.email)`

## Push Notifications

Implementing push notifications requires a few additional snippets of code to enable.: 
1. Registering users for push notifications.
2. Sending resulting push tokens to Klaviyo.
3. Handlinge when users attempt to open your push notifications.

### Sending push notifications

1. Add the following code to your application wherever you would like to prompt users to register for push notifications. This is often included within `application:didFinishLaunchingWithOptions:`, but it can be placed elsewhere as well. When this code is called, ensure that the Klaviyo SDK has beenis configured and that `setUpUserEmail:` has beenis called. This enables Klaviyo to match app tokens with profiles in Klaviyocustomers.

```swift
    import UserNotifications
...

    let center = UNUserNotificationCenter.current()
    center.delegate = self as? UNUserNotificationCenterDelegate
    let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]

    center.requestAuthorization(options: options) { (granted, error) in
        // Enable / disable features based on response
    }
    UIApplication.shared.registerForRemoteNotifications()
```

2. Add the following code to the application delegate file in  `application:didRegisterForRemoteNotificationsWithDeviceToken`. You may need to add this code to your application delegate if you have not done so already.

```swift
    func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Klaviyo.sharedInstance.addPushDeviceToken(deviceToken: deviceToken)
    }
```

Any users that enable/accept push notifications from your app now will be eligible to receive your custom notifications.

To read more about sending push notifications, check out our additional push notification guides.
* [How to set up push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971)
* [How to send a push notification campaign](https://help.klaviyo.com/hc/en-us/articles/360006653972)
* [How to add a push notification to a flow](https://help.klaviyo.com/hc/en-us/articles/12932504108571)

### Tracking push notifications

The following code example allows you to track when a user opens a push notification.

1. In your application delegate, under `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` add the following:

```swift 
if application.applicationState == UIApplication.State.inactive || application.application.State == UIApplicationState.background {
    Klaviyo.sharedInstance.handlePush(userInfo: userInfo as NSDictionary)
  }
    completionHandler(.noData)
```

2. Add the following code that extends your app delegate:

```swift
    extension AppDelegate: UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
            Klaviyo.sharedInstance.handlePush(userInfo: response.notification.request.content.userInfo as NSDictionary)
            completionHandler()
        }
    }
    
```

Once your first push notifications are sent and opened, you should start to see *Opened Push* metrics within your Klaviyo dashboard.

### Foreground push handling

The following code example allows push notifications to appearshow when your app is running:

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

