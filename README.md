# KlaviyoSwift

[![CI Status](https://travis-ci.org/klaviyo/klaviyo-swift-sdk.svg?branch=master)](https://travis-ci.org/klaviyo/klaviyo-swift-sdk)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![Platform](https://img.shields.io/cocoapods/p/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)

## Overview

KlaviyoSwift is an SDK, written in Swift, for users to incorporate Klaviyo's event tracking functionality into iOS applications. We also provide an SDK written in [Objective-C](https://github.com/klaviyo/klaviyo-objc-sdk). The two SDKs are identical in their tracking functionality. **However, the KlaviyoSwift SDK is the only one that supports push notifications**. We strongly encourage the use of the KlaviyoSwift SDK.

## Requirements
- iOS 9.0+ 
- Xcode 10.1+
- Swift 4.2+

## Installation Options

1. CocoaPods (recommended)
2. Download a blank, pre-configured project, and get started from scratch. 
3. Download the zip file, and drag and drop the KlaviyoSwift file into your project. 

Note that options two and three will require you to repeat those steps as our SDK is updated. By using CococaPods the library can be kept up-to-date via `pod update`.

## CocoaPods
KlaviyoSwift is available through [CocoaPods](https://cocoapods.org/?q=klaviyo). To install
it, simply add the following line to your Podfile:

```ruby
pod "KlaviyoSwift"
```

## Example Usage: Event Tracking

To run the example project, clone the repo, and run `pod install` from the Example directory first. Make sure any .swift files using the Klaviyo SDK contain the import call.

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

As of right now, anonymous tracking is *not enabled by default*. What this means is that you cannot call `trackEvent` with only the eventName parameter unless `setUpUserEmail` has been called previously. Contact your account manager to make a request to enable anonymous tracking.

Once anonymous tracking is enabled for your account you will be able to track events without any user information provided. In the meantime, make sure to pass in an email or `$id` identifier in order for Klaviyo to track events successfully.

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
To be able to send push notifications, you must add two snippets of code to your application. One to register users for push notifications, and one that will send Klaviyo their tokens. 

Add the below code to your application wherever you would like to prompt users to register for push notifications. This is often included within `application:didFinishLaunchingWithOptions:`, but it can be placed elsewhere as well. Make sure that whenever this code is called that the Klaviyo SDK has been configured and that `setUpUserEmail:` has been called. This is so that Klaviyo can match app tokens with customers.

```swift
    import UserNotifications

...

    if #available(iOS 10, *) {
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        if #available(iOS 12.0, *) {
            options = UNAuthorizationOptions(rawValue: options.rawValue | UNAuthorizationOptions.provisional.rawValue)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: options) { (granted, error) in
            // Enable / disable features based on response
        }
        UIApplication.shared.registerForRemoteNotifications()
    } else {
        let types : UIUserNotificationType = [.alert, .badge, .sound]
        let setting = UIUserNotificationSettings(types:types, categories:nil)
        UIApplication.shared.registerUserNotificationSettings(setting)
        UIApplication.shared.registerForRemoteNotifications()
    }
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

In your application delegate, under `application:didFinishLaunchingWithOptions:` add the following:

```swift 
    if let launch = launchOptions, let data = launch[UIApplicationLaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
        Klaviyo.sharedInstance.handlePush(userInfo: data as NSDictionary)
    }
```

Under `application:didReceiveRemoteNotification:` add the following:
``` 
func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    
    if application.applicationState == UIApplicationState.inactive || application.applicationState ==  UIApplicationState.background {
        Klaviyo.sharedInstance.handlePush(userInfo: userInfo as NSDictionary)
    }
```

That is all you need to do to track opens. Now once your first push notifications have been sent and been opened, you should start to see `Opened Push` metrics within your Klaviyo dashboard.

## Authors

Katy Keuper, Chris Conlon (chris.conlon@klaviyo.com)

## License

KlaviyoSwift is available under the MIT license. See the LICENSE file for more info.

