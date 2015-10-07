# KlaviyoSwift

[![CI Status](http://img.shields.io/travis/Katy Keuper/KlaviyoSwift.svg?style=flat)](https://travis-ci.org/Katy Keuper/KlaviyoSwift)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![Platform](https://img.shields.io/cocoapods/p/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)

## Overview

KlaviyoSwift is an SDK, written in Swift, for users to incorporate Klaviyo's event tracking functionality into iOS applications. We also provide an SDK written in [Objective-C](https://github.com/klaviyo/klaviyo-objc-sdk). The two SDKs are identical in their functionality.

## Requirements
*iOS >= 8.0
*Swift 2.0 & XCode 7.0

## Installation Options

1. Cocoapods (recommended)
KlaviyoSwift is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "KlaviyoSwift"
```
2. Download a blank, pre-configured project, and get started from scratch. 

## Example Usage: Event Tracking

To run the example project, clone the repo, and run `pod install` from the Example directory first. Make sure any .swift files using the Klaviyo SDK contain the import call.

```swift
import KlaviyoSwift
```

Adding Klaviyo's tracking functionality requires just a few lines of code. To get started, add the following line to AppDelegate.swift, within application:didFinishLaunchingWithOptions:

```swift 
Klaviyo.setupWithPublicAPIKey("YOUR_PUBLIC_API_KEY")
```

```swift

let klaviyo = Klaviyo.sharedInstance

let customerDictionary : NSMutableDictionary = NSMutableDictionary()
customerDictionary[klaviyo.KLPersonEmailDictKey] = "john.smith@example.com"
customerDictionary[klaviyo.KLPersonFirstNameDictKey] = "John"
customerDictionary[klaviyo.KLPersonLastNameDictKey] = "Smith"

let propertiesDictionary : NSMutableDictionary = NSMutableDictionary()
propertiesDictionary["Total Price"] = 10.99
propertiesDictionary["Items Purchased"] = ["Milk","Cheese", "Yogurt"]
Klaviyo.sharedInstance.trackEvent("Completed Checkout", customerProperties: customerDictionary, properties: propertiesDictionary)
```

## Example Usage: Identifying traits of People

Assuming that `setupWithPublicAPIKey` has already been implemented elsewhere in the application, you can identify traits about a person using `trackPersonWithInfo`:

```swift
let klaviyo = Klaviyo.sharedInstance

let personInfoDictionary : NSMutableDictionary = NSMutableDictionary()
personInfoDictionary[klaviyo.KLPersonEmailDictKey] = "john.smith@example.com"
personInfoDictionary[klaviyo.KLPersonZipDictKey] = "02215"


klaviyo.trackPersonWithInfo(personInfoDictionary)
```

## Argument Description

The `track` function can be called with anywhere between 1-4 arguments:

`eventName` This is the name of the event you want to track. It can be any string. At a bare minimum this must be provided to track and event.

`customer_properties` (optional, but recommended) This is a NSMutableDictionary of properties that belong to the person who did the action you're recording. If you do not include an $email or $id key, the user will be tracked by an $anonymous key.

`properties` (optional) This is a NSMutableDictionary of properties that are specific to the event. In the above example we included the items purchased and the total price.

`eventDate` (optional) This is the timestamp (an NSDate) when the event occurred. You only need to include this if you're tracking past events. If you're tracking real time activity, you can ignore this argument.

Note that the only argument `trackPersonWithInfo` takes is a dictionary representing a customer's attributes. This is different from `trackEvent`, which can take multiple arguments.

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
    Klaviyo.sharedInstance.setUpUserEmail("john.smith@example.com")
```

## Author

Katy Keuper, katy.keuper@klaviyo.com

## License

KlaviyoSwift is available under the MIT license. See the LICENSE file for more info.
