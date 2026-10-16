# Klaviyo Swift Examples

## Overview

This repository includes a few sample apps that demonstrate how to integrate the Klaviyo Swift SDK into your app. We will update this repo as we make new releases and add new features to the Swift SDK.

## Cocoapods Example

This [example](CocoapodsExample) shows to create an app that integrates the Klaviyo Swift via cocoapods. There is a sample podfile which specifies the Swift SDK as a dependency. If your app uses Cocoapods you would add a similar dependency to your Podfile and run:

```bash
pod install
```

## SPM Example

This [example](SPMExample) demonstrates how to integrate our SDK using SPM. Follow the [installation steps](../../README.md#installation) to integrate it in your app.

## SPM Example — Automatic Push Tracking

This [example](SPMExample/SPMExampleAutomatic) mirrors the SPM Example but opts into automatic push integration via two independent Info.plist keys: `klaviyo_automatic_push_open_tracking` (tracks push opens) and `klaviyo_automatic_push_token_forwarding` (forwards device tokens). With both keys set, the SDK automatically forwards device tokens and tracks push opens, so no `didRegisterForRemoteNotificationsWithDeviceToken` or `UNUserNotificationCenterDelegate` code is required in your `AppDelegate`.

## Which example should I use?

| Example | Integration style | When to choose |
|---|---|---|
| `SPMExample` | Manual (STEP1–STEP6) | You want full control over push delegate callbacks, or you need to handle non-Klaviyo notifications alongside Klaviyo ones. |
| `CocoapodsExample` | Manual (CocoaPods) | Same as above, but your project uses CocoaPods instead of SPM. |
| `SPMExampleAutomatic` | Automatic (plist opt-in) | You want zero push code in your `AppDelegate` and are happy for the SDK to handle token registration and open tracking automatically. |

## In-app form personalization

All three apps in this repository share the auth token provider toggle below the email input on the welcome screen. Enable it to reveal the pasted JWT field. Configure your public API key, paste a JWT for the profile you will log in as, and use the existing login controls to identify that profile. When switching profiles, paste that profile's freshly issued JWT before changing the identified profile; the SDK may invoke the provider immediately. Logout resets the SDK profile; the provider stays registered until you turn it off. The token and toggle are kept only in memory and reset when the app restarts.

For a repeatable manual check, configure a live personalized in-app form to trigger on the **Added to Cart** metric. Enable the provider, paste a fresh JWT for the matching profile, log in as that profile, then tap **Add to Cart** on a menu item. That action emits **Added to Cart** after identification, so you can trigger the form when the JWT is available.

While logged in, tap the zipcode/email footer with the lock icon to open the auth token provider drawer. The drawer slides over the menu within the same screen; tap its close button or the dimmed background to dismiss it. It contains the same toggle and pasted JWT field as the welcome screen. Paste a fresh token there without logging out; dismissing and reopening the drawer preserves the current value. You can also disable and re-enable the provider from the drawer.

The registered provider reads the current field value each time the SDK requests a token. Editing the field does not register the provider again or invalidate a token the SDK has already cached. Empty or whitespace-only input makes the provider throw an error without including the token in the error.

A pasted static JWT demonstrates initial personalization. To exercise refresh, open the footer drawer while logged in and replace the field value with a freshly issued JWT before the next provider call. Editing the token does not reset the profile or force a token fetch. Dismiss the drawer, wait for the cached token to need refresh, and trigger the form again. Disable the provider in the drawer to unregister it; re-enable it to register it again with the current field value. For a real integration, replace the example closure with a request to your authentication server that returns a fresh JWT on every invocation; the source marks that spot with `Fetch a fresh JWT from your authentication server here.`

Use an SDK build containing `registerAuthTokenProvider` and `unregisterAuthTokenProvider`; the CocoaPods example requires those APIs in its installed pods as well.

## Previewing draft in-app forms

To see an unpublished in-app form on a device or simulator, open the form in the Klaviyo in-app form editor, click **Preview on device** and copy the preview token. In any of the example apps, turn on **Forms preview** below the auth token provider toggle (on the welcome screen, or in the footer drawer while logged in) to show the preview token field. Paste the token and tap **Set**. The draft form appears and refreshes about every 4 seconds, so edits saved in the editor show up without restarting the app. Tokens expire after 30 minutes; mint a new one in the editor when that happens.

Turn **Forms preview** off to clear the token and return to published forms. `AppState` in [ContentView.swift](./Shared/ContentView.swift) keeps the token in memory only and passes it to `KlaviyoSDK().setFormsPreviewToken(_:)`; it is never persisted or logged. Preview tokens are for testing only and must not ship in a production build.

## Authors

Klaviyo Mobile Push Team

## License

KlaviyoSwift is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
