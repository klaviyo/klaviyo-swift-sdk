# KlaviyoSwift

[![CI Status](https://travis-ci.org/klaviyo/klaviyo-swift-sdk.svg?branch=master)](https://travis-ci.org/klaviyo/klaviyo-swift-sdk)
[![Swift](https://img.shields.io/badge/Swift-5.3_5.4_5.5_5.6_5.7-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.3_5.4_5.5_5.6_5.7-Orange?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![Platform](https://img.shields.io/cocoapods/p/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)


## Overview

KlaviyoSwift is an SDK, written in Swift that can be integrated into your iOS App. This will allow you to message your users via push notifications from Klaviyo. In addition you will be able to take advantage of Klaviyo's identification and event tracking functionality. Once integrated, your marketing team will be able to better understand your app users' needs and send them timely messages via APNS.

## Installation Options

1. SPM 
1. CocoaPods

## SPM
KlaviyoSwift is available via [Swift Package Manager (SPM)](https://swift.org/package-manager/). Follow the steps below to get it setup.

### Import the SDK
Open your project and navigate to your project’s settings. Select the Swift Packages tab and click on the add button below the packages list. Enter the URL of our Swift SDK repository (https://github.com/klaviyo/klaviyo-swift-sdk) in the text field and click Next. On the next screen, select the SDK version (1.7.0 as of this writing) and click Next.

### Select the Package
Select the `KlaviyoSwift` package and click Finish.  


## CocoaPods
KlaviyoSwift is available through [CocoaPods](https://cocoapods.org/?q=klaviyo). To install
it, simply add the following line to your Podfile:

```ruby
pod "KlaviyoSwift"
```

Then run `pod install` to complete the integration.
The library can be kept up-to-date via `pod update`.

## Example Usage: Event Tracking

Once integration is complete you can begin tracking events in your app. First, make sure any .swift files using the Klaviyo SDK contain the import call.

```swift
import KlaviyoSwift
```

Adding Klaviyo's tracking functionality requires just a few lines of code. To get started, add the following line to AppDelegate.swift, within application:didFinishLaunchingWithOptions:

```swift 
Klaviyo.setupWithPublicAPIKey(apiKey: "YOUR_KLAVIYO_PUBLIC_API_KEY")
```

Once Klaviyo has been set up, you can begin tracking events anywhere within your application. Simply call Klaviyo's `trackEvent` method in the relevant location.

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

## Example Usage: Identifying traits of People

Assuming that `setupWithPublicAPIKey` has already been implemented elsewhere in the application, you can identify traits about a person using `trackPersonWithInfo`:

```swift
let klaviyo = Klaviyo.sharedInstance

let personInfoDictionary : NSMutableDictionary = NSMutableDictionary()
personInfoDictionary[klaviyo.KLPersonEmailDictKey] = "john.smith@example.com"
personInfoDictionary[klaviyo.KLPersonZipDictKey] = "02215"


klaviyo.trackPersonWithInfo(personDictionary: personInfoDictionary)
```

## Argument Description

The `track` function can be called with anywhere between 1-4 arguments:

`eventName` This is the name of the event you want to track. It can be any string. At a bare minimum this must be provided to track an event.

`customerProperties` (optional, but recommended) This is a NSMutableDictionary of properties that belong to the person who did the action you're recording. If you do not include an $email or $id key, the event cannot be tracked by Klaviyo. 

`properties` (optional) This is a NSMutableDictionary of properties that are specific to the event. In the above example we included the items purchased and the total price.

`eventDate` (optional) This is the timestamp (an NSDate) when the event occurred. You only need to include this if you're tracking past events. If you're tracking real time activity, you can ignore this argument.

Note that the only argument `trackPersonWithInfo` takes is a dictionary representing a customer's attributes. This is different from `trackEvent`, which can take multiple arguments.

## Anonymous Tracking Notice

By default, Klaviyo will begin tracking unidentified users in your app once the SDK is initialized. This means you will be able to track events from users in your app without any user information provided. When an email or other primary identifier is provided Klaviyo will merge the data from the anonymous user to a new identified user. Prior to version 1.7.0, the Klaviyo SDK used the [Apple identifier for vendor (IDFV)](https://developer.apple.com/documentation/uikit/uidevice/1620059-identifierforvendor) to facilitate anonymous tracking. Starting with version 1.7.0, the SDK will use a cached UUID that is generated when the SDK is initialized. For existing anonymous profiles using IDFV, the SDK will continue to use IDFV, instead of generating a new UUID.

## Integrating with Shopify's Mobile SDK
If your application makes use of Shopify's Mobile Buy SDK, then Klaviyo can easily port that data into your Klaviyo account. Simply add the following line of code to your app within your Shopify completion handler or wherever your checkout code creates Shopify's `BuyCheckout` instance (if it is within the completion handler, it should be referenced as `checkout`. If you are building the checkout object manually then use whichever name you created):

` Klaviyo.sharedInstance.setUpUserEmail(userEmail: checkout.email)`

## Special Properties

As was shown in the event tracking example, special person and event properties can be used. This works in a similar manner to the [Klaviyo Analytics API](https://www.klaviyo.com/docs). These are special properties that can be utilized when identifying a user or event. They are:
    
    KLPersonEmailDictKey 
    KLPersonFirstNameDictKey
    KLPersonLastNameDictKey
    KLPersonPhoneNumberDictKey
    KLPersonTitleDictKey
    KLPersonOrganizationDictKey
    KLPersonCityDictKey
    KLPersonRegionDictKey
    KLPersonCountryDictKey
    KLPersonZipDictKey
    KLEventIDDictKey
    KLEventValueDictKey

Lastly, cases where you wish to call `trackEvent` with only the eventName parameter and not have it result in anoynmous user tracking, you can use `setUpUserEmail` to configure your user's email address. By calling this once, usually upon application login, Klaviyo can track all subsequent events as tied to the given user. However, you are also free to override this functionality by passing in a customer properties dictionary at any given time:

```swift
    Klaviyo.sharedInstance.setUpUserEmail(userEmail: "john.smith@example.com")
```
## Sending Push Notifications
To be able to send push notifications, you must add a few snippets of code to your application. One to register users for push notifications, one that will send resulting push tokens to Klaviyo, and some final snippets to handle when users attempt to open your push notifications.

Add the below code to your application wherever you would like to prompt users to register for push notifications. This is often included within `application:didFinishLaunchingWithOptions:`, but it can be placed elsewhere as well. Make sure that whenever this code is called that the Klaviyo SDK has been configured and that `setUpUserEmail:` has been called. This is so that Klaviyo can match app tokens with customers.

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

Add the below line of code to the application delegate file in  `application:didRegisterForRemoteNotificationsWithDeviceToken:` (note that you might need to add this code to your application delegate if you have not done so already)

```swift
    func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Klaviyo.sharedInstance.addPushDeviceToken(deviceToken: deviceToken)
    }
```

That's it! Now any users that accept push notifications from your app will be eligible to receive your custom notifications.
For information on how to send push notifcations through Klaviyo, please check our support docs.

## Tracking Push Notifications

If you would like to track when a user opens a push notification then there is a little more code that you will need to add to your application.

In your application delegate, under `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` add the following:

```swift 
if application.applicationState == UIApplication.State.inactive || application.application.State == UIApplicationState.background {
    Klaviyo.sharedInstance.handlePush(userInfo: userInfo as NSDictionary)
  }
    completionHandler(.noData)
```

In addition please add the following code that extends your app delegate:

```swift
    extension AppDelegate: UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
            Klaviyo.sharedInstance.handlePush(userInfo: response.notification.request.content.userInfo as NSDictionary)
            completionHandler()
        }
    }
    
```

That is all you need to do to track opens. Now once your first push notifications have been sent and been opened, you should start to see `Opened Push` metrics within your Klaviyo dashboard.

## [OPTIONAL] Foreground Push Handling

The code below will enable push notifications to show up when you app is running:

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

If your user taps on the notification this will be tracked back to Klaviyo as an "Opened Push" event assuming you have implemented the tracking changes discussed above.

## SDK Data Transfer

Starting with version 1.7.0, the SDK will cache incoming data and flush it back to the Klaviyo API on an interval. As of this writing the interval is based on the network link currently being used by the app. The table below shows the flush interval used for each type of connection:

| Network     | Interval    |
| :---        | :--- |
| WWAN/Wifi   | 10 seconds  |
| Cellular    | 30 seconds  |

Connection determination is based on notifications from our reachability service. When there is no network available the SDK will cache data until the network becomes available again. All data sent by the SDK should be available shortly after it is flushed by the SDK. 

### Retries

The SDK will retry API requests that fail under certain conditions. For example if a network timeout occurs the request will be retried on the next flush interval. In addition if the SDK receives a rate limiting error (429) from the Klaviyo API it will use exponential backoff with jitter to retry the next request.

## License

KlaviyoSwift is available under the MIT license. See the LICENSE file for more info.
