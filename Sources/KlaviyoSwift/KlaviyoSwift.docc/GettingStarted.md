# Getting Started

Install the Klaviyo Swift SDK and initialize it with your public API key.

## Overview

The Klaviyo Swift SDK lets you add Klaviyo's analytics and push notification features to your iOS
app. The SDK identifies users and tracks events through the
[Klaviyo Client APIs](https://developers.klaviyo.com/en/reference/api_overview). To reduce
performance overhead, it queues API requests and sends them in batches. The queue is persisted to
local storage, so data isn't lost if the device is offline or the app is terminated.

Once the SDK is integrated, your marketing team can better understand your app users' needs and send
them timely messages through APNs.

The SDK is split into products that you add as you need them:

| Product | Add it to | Use it for |
|---|---|---|
| `KlaviyoSwift` | Your app target | Profiles, events, push notifications, deep links |
| `KlaviyoForms` | Your app target | [In-app forms](/documentation/klaviyoforms/inappforms) |
| `KlaviyoLocation` | Your app target | [Geofencing](/documentation/klaviyolocation/geofencing) |
| `KlaviyoSwiftExtension` | Your Notification Service Extension target | [Rich push, badge counts and action buttons](/documentation/klaviyoswiftextension/notificationserviceextension) |

## Prepare your Xcode project

1. Enable the push notification capability in your Xcode project. The section "Enable the push
   notification capability" in Apple's guide to
   [registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering_your_app_with_apns#2980170)
   has detailed instructions.
2. If you intend to use rich push notifications, custom badge counts or custom data, add a
   Notification Service Extension and an App Group to your project. See
   [Setting Up a Notification Service Extension](/documentation/klaviyoswiftextension/notificationserviceextension)
   for the steps.

## Install the SDK

Install the SDK with the dependency manager your app uses.

### Swift Package Manager (recommended)

`KlaviyoSwift`, `KlaviyoForms`, `KlaviyoLocation` and `KlaviyoSwiftExtension` are available through
[Swift Package Manager](https://swift.org/package-manager).

1. Open your project and navigate to your project's settings.
2. Select the **Package Dependencies** tab and click the **add** button below the packages list.
3. Enter the URL of the Swift SDK repository, `https://github.com/klaviyo/klaviyo-swift-sdk`, in the
   text field. This brings up the package on the screen.
4. For the dependency rule dropdown, select **Up to Next Major Version** and leave the pre-filled
   versions as they are.
5. Click **Add Package**.
6. On the next prompt, assign the package products `KlaviyoSwift`, `KlaviyoForms` and
   `KlaviyoLocation` to your app target, and `KlaviyoSwiftExtension` to the Notification Service
   Extension target (if you created one). Click **Add Package**.

### CocoaPods

`KlaviyoSwift` is available through [CocoaPods](https://cocoapods.org/pods/KlaviyoSwift).

1. Add the following lines to your Podfile, including only the pods you use. Replace `YourAppTarget` and
   `YourAppNotificationServiceExtensionTarget` with the names of your app and Notification Service
   Extension targets.

   ```ruby
   target 'YourAppTarget' do
     pod 'KlaviyoSwift'
     pod 'KlaviyoForms'
     pod 'KlaviyoLocation'
   end

   target 'YourAppNotificationServiceExtensionTarget' do
     pod 'KlaviyoSwiftExtension'
   end
   ```

2. Run `pod install` to complete the integration.

Keep the libraries up to date with `pod update`, for example `pod update KlaviyoSwift KlaviyoForms
KlaviyoLocation KlaviyoSwiftExtension`.

## Initialize the SDK

Initialize the SDK with the short alphanumeric
[public API key](https://help.klaviyo.com/hc/en-us/articles/115005062267#difference-between-public-and-private-api-keys1)
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

Initialize the SDK with ``KlaviyoSDK/initialize(with:)`` before you call any other Klaviyo SDK method.

## Identify notifications from other providers

If you use more than one push provider, import `KlaviyoSwift` and check
``UserNotifications/UNNotificationResponse/isKlaviyoNotification`` to tell whether a notification
came from Klaviyo.

## Next steps

- <doc:ProfilesAndEvents>
- <doc:PushNotifications>
- <doc:DeepLinking>
