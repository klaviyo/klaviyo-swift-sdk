# Migration Guide

Update your integration when you move to a newer major or minor version of the SDK.

## Overview

This guide outlines how to migrate from older versions of the SDK to newer ones. Sections are
ordered from the newest release to the oldest.

## Migrating to v5.5.0

### In-app forms

`formCtaClicked` now fires for in-app deep links even when the link couldn't be opened, not only when
navigation succeeds. If you use this event as a "navigation happened" signal, you may see it for dead
links. This already matched how the event behaved for external URLs. See
[In-App Forms](/documentation/klaviyoforms/inappforms#Monitor-form-lifecycle-events).

## Migrating to v5.4.0

### Automatic push integration flags (opt-in)

SDK 5.4.0 introduces two opt-in behaviors for push notifications, controlled through your app's
`Info.plist`. Both flags default to **off**; no action is required to keep the existing behavior.

**`klaviyo_automatic_push_open_tracking`:** when set to `true`, the SDK injects a proxy
`UNUserNotificationCenterDelegate` to record push-open events automatically. You no longer need to
call ``KlaviyoSDK/handle(notificationResponse:withCompletionHandler:)`` yourself.

```xml
<!-- Info.plist -->
<key>klaviyo_automatic_push_open_tracking</key>
<true/>
```

**`klaviyo_automatic_push_token_forwarding`:** when set to `true`, the SDK automatically swizzles
your app delegate to capture APNs device tokens and forward them to Klaviyo. You no longer need to
call ``KlaviyoSDK/set(pushToken:)-(Data)`` yourself.

```xml
<!-- Info.plist -->
<key>klaviyo_automatic_push_token_forwarding</key>
<true/>
```

**Rollout summary:**

| Behavior | This release (5.4.0) | Future major release |
|---|---|---|
| `klaviyo_automatic_push_open_tracking` | Opt-in (default off) | Default on (opt-out) |
| `klaviyo_automatic_push_token_forwarding` | Opt-in (default off) | Default on (opt-out) |

> Note: If you enable `klaviyo_automatic_push_token_forwarding`, the SDK registers an anonymous
> profile with Klaviyo as soon as it gets a device token, before any call to
> ``KlaviyoSDK/set(profile:)``, ``KlaviyoSDK/set(email:)`` or ``KlaviyoSDK/set(phoneNumber:)``. This is
> expected: the anonymous profile is merged with the identified profile once you provide
> identifiers. See <doc:ProfilesAndEvents#Anonymous-tracking>.

For the full setup, see <doc:PushNotifications#Option-A-Automatic-integration>.

## Migrating to v5.3.1

> Note: v5.3.0 introduced a dependency on `KlaviyoCore` in `KlaviyoSwiftExtension` that's
> incompatible with Notification Service Extension targets. If your extension target has
> `APPLICATION_EXTENSION_API_ONLY = YES`, skip v5.3.0 and use v5.3.1 or later.

## Migrating to v5.1.0

### Custom deep link handling

`handle(notificationResponse:withCompletionHandler:deepLinkHandler:)` is deprecated and will be
removed in the next major version of the SDK. It's replaced by
``KlaviyoSDK/handle(notificationResponse:withCompletionHandler:)``. If you provided your own deep
link handling logic through the deprecated method, register it with
``KlaviyoSDK/registerDeepLinkHandler(_:)`` instead. For more information, see <doc:DeepLinking>.

### Handling universal links

This version improves universal link support, so links delivered in email campaigns can be opened in
your app *and* tracked as a Klaviyo profile event when tapped. We encourage you to adopt this to get
full support for universal links. See <doc:DeepLinking#Handle-universal-links>.

## Migrating to v5.0.0

### In-app forms

Because of the changes below, you may want to revisit when you call `registerForInAppForms()` when
upgrading from 4.2.0–4.2.1, especially if you registered more than once per app session. See
[In-App Forms](/documentation/klaviyoforms/inappforms) for the current integration instructions.

**Updated behaviors:**

- In versions 4.2.0–4.2.1, calling `registerForInAppForms()` worked like a "fetch" that checked
  whether a form was available and, if so, displayed it. Version 5.0.0 changes this so that
  `registerForInAppForms()` sets up a persistent listener that's ready to display a form if and when
  one is targeted to the current profile.
- A deep link from an in-app form is now issued *after* the form has closed, instead of during the
  close animation. This prevents a race condition when the host app expects the form to be closed
  before it handles the deep link.

**Configurable session timeout:** an optional argument to `registerForInAppForms()` configures the
in-app forms session timeout, which defaults to 60 minutes.

**New `unregisterFromInAppForms()` method:** because `registerForInAppForms()` is now a persistent
listener rather than a "fetch", you can call `unregisterFromInAppForms()` to stop listening for
in-app forms at appropriate times, such as when a user logs out. See
[In-App Forms](/documentation/klaviyoforms/inappforms#Unregister-from-in-app-forms).

## Migrating to v4.0.0

### Event.EventName enum

- The PascalCase names in the `Event.EventName` enum have been removed, leaving only the camelCase
  names. Remove any references to the old PascalCase names. See
  <doc:MigrationGuide#Migrating-to-v3.3.0> for details.
- The `.OpenedPush` case has been removed (there's no camelCase replacement), because it's intended
  for internal use only. Remove any references to `.OpenedPush`.

## Migrating to v3.3.0

The case names in the `Event.EventName` enum changed from PascalCase to camelCase, to be consistent
with [Swift naming conventions](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/enumerations/).
The old PascalCase names stayed in place with the same behavior as the new camelCase names, and were
removed in v4.0.0. Direct references to the old names show a deprecation warning, with an option to
"fix" the name by replacing it with the camelCase version.

This update is non-breaking for most use cases, but code that `switch`es over the `Event.EventName`
enum needs minor changes. There are two scenarios:

1. If the `switch` statement has no `default` case, the compiler reports a "Switch must be
   exhaustive" error. You can click "Fix" to have Xcode add the missing cases, but we recommend that
   you add the new camelCase names alongside the old ones in your branching logic. For example:

   ```swift
   switch event {
   case .OpenedPush:
       <...>
   case .OpenedAppMetric, .openedAppMetric:
       <...>
   case .ViewedProductMetric, .viewedProductMetric:
       <...>
   case .AddedToCartMetric, .addedToCartMetric:
       <...>
   case .StartedCheckoutMetric, .startedCheckoutMetric:
       <...>
   case .CustomEvent(let string), .customEvent(let string):
       <...>
   }
   ```

2. If the `switch` statement does have a `default` case, logic for the new camelCase names falls into
   the `default` case unless you update the statement. We recommend updating it as described in (1).

## Migrating to v3.0.0

Deprecated event type enum cases have been removed. See <doc:MigrationGuide#Migrating-to-v2.4.0> for
the reasoning and code samples.

## Migrating to v2.4.0

The Swift SDK was found to use legacy event names for some common events, such as "Viewed Product",
and for some events associated with server actions, such as "Ordered Product". As a result, if your
account used these enum cases, they were logged with names like "$viewed_product", while
website-generated events are logged as "Viewed Product".

To bring the Swift SDK in line with Klaviyo's other integrations, the incorrect enum cases were
deprecated and new cases were introduced with corrected spellings where appropriate. The deprecated
cases were removed in the next major release.

```swift
// Old code: using one of the legacy enum cases
let event = Event(name: .ViewedProduct)

// New code: update to new case with -Metric suffix
let event = Event(name: .ViewedProductMetric)
```

If you use any of the old names and need to keep them, use the custom case, for example:

```swift
let event = Event(name: .Custom("$viewed_product"))
```

## Migrating from v1.X.0 to v2.0.0

Version 2.0.0 of the iOS SDK updates the API to take advantage of modern Swift language features,
which makes it easier to integrate into Swift apps. The old `Klaviyo` class was deprecated and has
since been removed.

### Singletons

The newer API no longer requires the singleton pattern. Code that references the shared instance,
like this:

```swift
Klaviyo.sharedInstance
```

can be converted to:

```swift
KlaviyoSDK()
```

### Profile identification

The previous SDK took a dictionary as input to track a profile:

```swift
let klaviyo = Klaviyo.sharedInstance
let personInfoDictionary : NSMutableDictionary = NSMutableDictionary()
personInfoDictionary[klaviyo.KLPersonEmailDictKey] = "john.smith@example.com"
personInfoDictionary[klaviyo.KLPersonZipDictKey] = "02215"
klaviyo.trackPersonWithInfo(personDictionary: personInfoDictionary)
```

Now you can do the same thing like this:

```swift
let profile = Profile(email: "john.smith@example.com", location: .init(zip: "02215"))
KlaviyoSDK().set(profile: profile)
```

### Tracking an event

Tracking an event is similar to before, but with stronger types. In the previous API you did this:

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

In v2.0.0 this became:

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

> Note: This shows the v2.0.0 API. Current versions no longer take `identifiers` or `profile` on
> `Event`: set the profile with ``KlaviyoSDK/set(profile:)`` and create the event with
> ``KlaviyoSDK/create(event:)``, as shown in <doc:ProfilesAndEvents#Track-events>.

### Setting your push token

Setting push tokens hasn't changed much. Previously you did this:

```swift
Klaviyo.sharedInstance.set(deviceToken: "your-token-here")
```

Now you can do this:

```swift
KlaviyoSDK().set(pushToken: "your-token-here")
```

### Tracking push opens

Tracking push opens is also a bit different. You can remove the code from
`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`. Your app delegate now needs
the following code:

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let handled = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: completionHandler)
        if !handled {
            // not a Klaviyo notification; should be handled by other app code
            completionHandler()
        }
    }
}
```

### Deep link updates

Handling deep links is very similar to earlier versions. However, if you use universal links, you
may want to update your code as follows:

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let handled = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: completionHandler) { url in
            // parse deep link and navigate here.
        }
        if !handled {
            // not a Klaviyo notification; should be handled by other app code
            completionHandler()
        }
    }
}
```

> Note: The `deepLinkHandler:` variant shown above was deprecated in v5.1.0. Register your handler
> with ``KlaviyoSDK/registerDeepLinkHandler(_:)`` instead; see
> <doc:MigrationGuide#Migrating-to-v5.1.0>.

### Updated example app

The example app includes examples of all of the above. If you have more questions, start a thread in
the [discussions](https://github.com/klaviyo/klaviyo-swift-sdk/discussions) section of the
repository.
