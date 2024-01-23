
# iOS SDK Migration Guide

This guide outlines how developers can migrate from older versions of our SDK to newer ones.

## Migrating to v3.0.0

Deprecated event type enum cases have been removed.
The reasoning is explained below, see [Migrating to v2.4.0](#Migrating-to-v240) for details and code samples.

## Migrating to v2.4.0

It was recently discovered that the Swift SDK was using legacy event names for some common events,
like "Viewed Product" and some events that are associated with server actions, like "Ordered Product."
As a result, if your account used these enum cases, they were being logged with names like "$viewed_product"
in contrast to website generated events which are logged as "Viewed Product."

In order to bring the Swift SDK in line with Klaviyo's other integrations, we've deprecated the incorrect enum cases
and introduced new cases to correct spellings where appropriate.
The deprecated cases will be removed in the next major release.

```swift
// Old code: using one of the legacy enum cases
let event = Event(name: .ViewedProduct)

// New code: update to new case with -Metric suffix
let event = Event(name: .ViewedProductMetric)
```

If you are using any of the old names and need to continue using them, you can use the custom enum e.g.
```swift
let event = Event(name: .Custom("$viewed_product"))
```

## Migrating from v1.X.0 to v2.0.0

Version 2.0.0 of the iOS SDK updates the API to take advantage of modern swift language features to make it easier to integrate
into your Swift applications. This means our old `Klaviyo` has been deprecated and it will be completely removed in a future SDK version.

### Singletons
The newer API no longer requires use of the singleton pattern. So any code that references the shared instance like this:
```swift
Klaviyo.sharedInstance
```
Can be converted to look like this:
```
KlaviyoSDK()
```

### Profile Identification
Our previous SDK used dictionary as input to track a profile like so:
```swift
let klaviyo = Klaviyo.sharedInstance
let personInfoDictionary : NSMutableDictionary = NSMutableDictionary()
personInfoDictionary[klaviyo.KLPersonEmailDictKey] = "john.smith@example.com"
personInfoDictionary[klaviyo.KLPersonZipDictKey] = "02215"
klaviyo.trackPersonWithInfo(personDictionary: personInfoDictionary)
```
Instead now the same thing can be acheived as follows:
```swift
let profile = Profile(email: "john.smith@example.com", location: .init(zip: "02215"))
KlaviyoSDK().set(profile: profile)
```

### Tracking an Event
Tracking an event is similar to before except again we are using stronger types. In our previous API you did this:
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
This now becomes:
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

### Setting your push token
Setting push tokens has not changed very much between versions. Where previously this was done:
```swift
Klaviyo.sharedInstance.set(deviceToken: "your-token-here")
```
Now you can do this:
```swift
KlaviyoSDK().set(pushToken: "your-token-here")
```

### Tracking Push Opens
Tracking push opens is also a bit different from before. You can now remove the code from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`. Also under your app delegate you now need the following code:
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

### Deep Link Updates
Handling deep link is very similar to how it was done in earlier versions however if you use universal links you may want to update your code as follows:
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

### Updated Example App
We've also updated the test app to include examples of all the above. If you have more questions feel free to drop us a line in the discussion section of this repo.
