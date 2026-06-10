# Klaviyo Swift Examples

## Overview

This repository includes a few sample apps that demonstrate how to integrate the Klaviyo Swift SDK into your app. We will update this repo as we make new releases and add new features to the Swift SDK.

## Cocoapods Example

This [example](CocoapodsExample) shows to create an app that integrates the Klaviyo Swift via cocoapods. There is a sample podfile which specifies the Swift SDK as a dependency. If your app uses Cocoapods you would add a similar dependency to your Podfile and run:

```bash
pod install
```

## SPM Example

This [example](SPMExample) demonstrates how to integrate our SDK using SPM. Follow the steps [here](../../README.md#installation) to integrate it in your app.

## SPM Example — Automatic Push Tracking

This [example](SPMExample/SPMExampleAutomatic) mirrors the SPM Example but opts in to automatic push integration via the `klaviyo_automatic_push_tracking` Info.plist key. With this key set, the SDK automatically forwards device tokens and tracks push opens — no `didRegisterForRemoteNotificationsWithDeviceToken` or `UNUserNotificationCenterDelegate` code required in your `AppDelegate`.

## Which example should I use?

| Example | Integration style | When to choose |
|---|---|---|
| `SPMExample` | Manual (STEP1–STEP6) | You want full control over push delegate callbacks, or you need to handle non-Klaviyo notifications alongside Klaviyo ones. |
| `CocoapodsExample` | Manual (CocoaPods) | Same as above, but your project uses CocoaPods instead of SPM. |
| `SPMExampleAutomatic` | Automatic (plist opt-in) | You want zero push code in your `AppDelegate` and are happy for the SDK to handle token registration and open tracking automatically. |

## Authors

Klaviyo Mobile Push Team

## License

KlaviyoSwift is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
